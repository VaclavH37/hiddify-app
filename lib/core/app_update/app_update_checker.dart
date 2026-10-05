import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/app_update/self_update.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/app_update/update_decision.dart';
import 'package:hiddify/core/app_update/update_keys.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/app_update/update_store.dart';
import 'package:hiddify/core/app_update/widget/app_update_dialog.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/utils/connected_loop.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:loggy/loggy.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_update_checker.g.dart';

/// What the About page and the dialog show.
class AppUpdateStatus {
  const AppUpdateStatus({this.offer, this.checking = false});

  /// A verified release newer than this build, or null.
  final UpdateManifest? offer;

  /// A check the user started is running.
  final bool checking;
}

/// Finds newer releases of the Windows EXE build and offers them.
///
/// Checks run only while connected and fetch only through the tunnel
/// (`proxyOnly`), like the rule-set updater: the first 2 to 5 minutes after
/// the connection comes up, then every [appUpdateCheckInterval]. A release is
/// trusted only once its manifest verifies against the keys pinned in
/// `update_keys.dart`.
///
/// Idle in every build without [kSelfUpdate], and on any platform but an
/// installed Windows build. Eager-started from `App.build` behind the same
/// constant, so other builds compile it out.
@Riverpod(keepAlive: true)
class AppUpdateChecker extends _$AppUpdateChecker {
  static final _log = Loggy('app_update');

  CancelToken? _inFlight;
  int? _promptedBuildThisRun;
  var _dialogOpen = false;

  @override
  AppUpdateStatus build() {
    if (!(kSelfUpdate && selfUpdatePlatform)) return const AppUpdateStatus();
    final random = Random();
    final loop = ConnectedLoop(
      check: _scheduledCheck,
      // After the rule-set check (30 s to 2 min), so the two fetches do not
      // land together, and spread across a crowd that reconnects at once.
      firstDelay: () => Duration(seconds: 120 + random.nextInt(181)),
      retryAfterFailure: appUpdateRetryAfterFailure,
      onStop: () => _inFlight?.cancel(),
    );
    ref.onDispose(loop.stop);
    ref.listen(connectionNotifierProvider, (_, next) {
      loop.connected(next.valueOrNull?.isConnected ?? false);
    }, fireImmediately: true);
    unawaited(_restoreOffer());
    return const AppUpdateStatus();
  }

  AppUpdateStore get _store => AppUpdateStore(ref.read(sharedPreferencesProvider).requireValue);

  Future<int?> _currentBuild() async {
    final info = await ref.read(appInfoProvider.future);
    final build = int.tryParse(info.buildNumber);
    if (build == null || build <= 0) _log.warning('app update: no build number, not checking');
    return build == null || build <= 0 ? null : build;
  }

  /// The offer a previous run found, so About shows it before the next check.
  Future<void> _restoreOffer() async {
    final build = await _currentBuild();
    if (build == null) return;
    final offer = await _store.loadOffer(pinnedKeys: kUpdatePublicKeys, channel: appUpdateChannel, currentBuild: build);
    if (offer != null && state.offer == null) state = AppUpdateStatus(offer: offer, checking: state.checking);
  }

  Future<AppUpdateCheckResult?> _check({required bool force}) async {
    final build = await _currentBuild();
    if (build == null) return null;
    final client = ref.read(httpClientProvider);
    final token = _inFlight = CancelToken();
    try {
      final result = await AppUpdateCheck(
        store: _store,
        manifestUrl: appUpdateManifestUrl(appUpdateBase, appUpdateChannel),
        channel: appUpdateChannel,
        currentBuild: build,
        pinnedKeys: kUpdatePublicKeys,
        fetch: (url, maxBytes) => client.getBytes(url, maxBytes: maxBytes, proxyOnly: true, cancelToken: token),
      ).run(force: force);
      state = AppUpdateStatus(offer: result.offer, checking: state.checking);
      return result;
    } finally {
      if (identical(_inFlight, token)) _inFlight = null;
    }
  }

  Future<Duration> _scheduledCheck() async {
    final result = await _check(force: false);
    if (result == null) return appUpdateCheckInterval;
    final offer = result.offer;
    final store = _store;
    if (offer != null &&
        shouldPromptForUpdate(
          offer,
          now: DateTime.now().toUtc(),
          promptedBuildThisRun: _promptedBuildThisRun,
          skippedBuild: store.skippedBuild,
          promptedBuild: store.promptedBuild,
          promptedAt: store.promptedAt,
        )) {
      // Not awaited: a dialog left open must not hold up the next check.
      unawaited(showOffer());
    }
    return result.next;
  }

  /// The About page's "Check for updates". Opens the dialog itself when it
  /// finds a release; the page reports the other outcomes.
  Future<AppUpdateOutcome> checkNow() async {
    if (state.checking) return AppUpdateOutcome.notDue;
    state = AppUpdateStatus(offer: state.offer, checking: true);
    try {
      final result = await _check(force: true);
      if (result == null) return AppUpdateOutcome.failed;
      if (result.outcome == AppUpdateOutcome.offered) unawaited(showOffer());
      return result.outcome;
    } catch (e) {
      _log.info('app update: manual check failed (${e.runtimeType})');
      return AppUpdateOutcome.failed;
    } finally {
      state = AppUpdateStatus(offer: state.offer);
    }
  }

  /// Puts the pending offer in front of the user and acts on the answer.
  Future<void> showOffer() async {
    final offer = state.offer;
    final context = rootNavKey.currentContext;
    if (offer == null || context == null || _dialogOpen) return;
    _dialogOpen = true;
    _promptedBuildThisRun = offer.build;
    final AppUpdateChoice? choice;
    try {
      await _store.recordPrompt(offer.build, DateTime.now().toUtc());
      if (!context.mounted) return;
      choice = await Navigator.of(context).push<AppUpdateChoice>(
        DialogRoute(
          context: context,
          builder: (_) => AppUpdateDialog(offer: offer),
        ),
      );
    } finally {
      _dialogOpen = false;
    }
    switch (choice) {
      case AppUpdateChoice.install:
        await _install(offer);
      case AppUpdateChoice.skip:
        _log.info('app update: ${offer.version} (${offer.build}) skipped');
        await _store.skip(offer.build);
      case AppUpdateChoice.later || null:
        break;
    }
  }

  /// For now the installer is fetched from the account page, as before. The
  /// download, verification and silent install replace this (U3).
  Future<void> _install(UpdateManifest offer) async {
    _log.info('app update: install ${offer.version} (${offer.build}) chosen');
    await UriUtils.tryLaunch(Uri.parse(Constants.accountUrl));
  }
}
