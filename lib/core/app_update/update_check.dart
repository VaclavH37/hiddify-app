import 'dart:convert';
import 'dart:typed_data';

import 'package:hiddify/core/app_update/update_decision.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/app_update/update_store.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/rulesets/ruleset_updater.dart' show describeMirrorError;
import 'package:loggy/loggy.dart';

/// Where releases are published: the rule-set mirror's bucket, under its own
/// `app/windows/` prefix. Public on purpose; the signature, not the host, is
/// what a client trusts.
const _appUpdateBase = 'https://cdn.raynlabs.io';

/// The update host. A diagnostics build may point it elsewhere for a live
/// test (a local server holding a manifest signed with the real key):
///
///   --dart-define=RAYN_DIAGNOSTICS=true
///   --dart-define=RAYN_UPDATE_BASE=http://localhost:8099
///
/// A shipped build ignores the define, like `Constants.rulesetMirrorBase`.
String get appUpdateBase {
  const override = String.fromEnvironment('RAYN_UPDATE_BASE');
  return Constants.diagnosticsBuild && override.isNotEmpty ? override : _appUpdateBase;
}

/// `stable`, or `test` in a diagnostics build that asks for it with
/// `--dart-define=RAYN_UPDATE_CHANNEL=test`. The publish tool writes both.
String get appUpdateChannel {
  const override = String.fromEnvironment('RAYN_UPDATE_CHANNEL');
  return Constants.diagnosticsBuild && override == 'test' ? 'test' : 'stable';
}

String appUpdateManifestUrl(String base, String channel) => '$base/app/windows/$channel/MANIFEST';

/// The installer's size as a whole number of megabytes (MiB, as Windows
/// counts them), at least 1. The unit is in the translated sentence.
int appUpdateMegabytes(int bytes) {
  final mb = (bytes / (1024 * 1024)).round();
  return mb < 1 ? 1 : mb;
}

enum AppUpdateOutcome {
  /// A newer release is waiting; [AppUpdateCheckResult.offer] holds it.
  offered,
  upToDate,

  /// The manifest arrived but was not one this client accepts.
  refused,

  /// The manifest could not be fetched.
  failed,

  /// Checked recently enough; nothing was fetched.
  notDue,
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult(this.outcome, {required this.next, this.offer});

  final AppUpdateOutcome outcome;

  /// When the next scheduled check should run.
  final Duration next;

  /// The verified offer pending after this check, if any.
  final UpdateManifest? offer;
}

typedef UpdateFetch = Future<Uint8List> Function(String url, int maxBytes);

/// One check: fetch the manifest, verify it against the pinned keys, decide,
/// and remember the outcome. The last check time is recorded only when the
/// host answered with something definite; a failed fetch is retried within
/// the hour.
class AppUpdateCheck {
  AppUpdateCheck({
    required this.store,
    required this.fetch,
    required this.manifestUrl,
    required this.channel,
    required this.currentBuild,
    required this.pinnedKeys,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppUpdateStore store;
  final UpdateFetch fetch;
  final String manifestUrl;
  final String channel;
  final int currentBuild;
  final Map<String, String> pinnedKeys;
  final DateTime Function() _clock;

  static final _log = Loggy('app_update');

  /// [force] skips the interval: the user asked from the About page.
  Future<AppUpdateCheckResult> run({bool force = false}) async {
    final now = _clock().toUtc();
    final last = store.lastCheck;
    if (!force && last != null) {
      final since = now.difference(last);
      if (!since.isNegative && since < appUpdateCheckInterval) {
        return AppUpdateCheckResult(
          AppUpdateOutcome.notDue,
          next: appUpdateCheckInterval - since,
          offer: await _stored(),
        );
      }
    }

    final Uint8List bytes;
    try {
      bytes = await fetch(manifestUrl, kUpdateMaxManifestBytes);
    } catch (e) {
      _log.info('app update: manifest unavailable (${describeMirrorError(e)})');
      return AppUpdateCheckResult(AppUpdateOutcome.failed, next: appUpdateRetryAfterFailure, offer: await _stored());
    }

    final String envelope;
    final UpdateManifest manifest;
    try {
      envelope = utf8.decode(bytes);
      manifest = verifyUpdateEnvelope(envelope, pinnedKeys);
    } on UpdateManifestException catch (e) {
      return _refused(now, e.reason);
    } on FormatException {
      return _refused(now, 'not UTF-8');
    }

    switch (updateDecision(
      manifest,
      channel: channel,
      currentBuild: currentBuild,
      seenPublishedAt: store.seenPublishedAt,
    )) {
      case UpdateRefused(:final why):
        return _refused(now, '${manifest.version} (${manifest.build}): $why');
      case UpdateNotNewer():
        _log.debug('app update: up to date (${manifest.build} published, $currentBuild running)');
        await store.recordSeen(manifest.publishedAt);
        await store.clearOffer();
        await store.recordCheck(now);
        return const AppUpdateCheckResult(AppUpdateOutcome.upToDate, next: appUpdateCheckInterval);
      case UpdateOffer():
        _log.info(
          'app update: ${manifest.version} (${manifest.build}) available'
          '${manifest.important ? ', marked important' : ''}',
        );
        await store.recordSeen(manifest.publishedAt);
        await store.saveOffer(envelope);
        await store.recordCheck(now);
        return AppUpdateCheckResult(AppUpdateOutcome.offered, next: appUpdateCheckInterval, offer: manifest);
    }
  }

  Future<AppUpdateCheckResult> _refused(DateTime now, String why) async {
    _log.warning('app update: manifest refused: $why');
    await store.recordCheck(now);
    return AppUpdateCheckResult(AppUpdateOutcome.refused, next: appUpdateCheckInterval, offer: await _stored());
  }

  Future<UpdateManifest?> _stored() =>
      store.loadOffer(pinnedKeys: pinnedKeys, channel: channel, currentBuild: currentBuild);
}
