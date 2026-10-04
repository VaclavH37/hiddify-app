import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:hiddify/core/rulesets/ruleset_store.dart';
import 'package:hiddify/core/rulesets/srs_check.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:loggy/loggy.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ruleset_updater.g.dart';

/// The same caps the mirror's pipeline enforces before publishing
/// (`hiddify-core/v2/config/ruleset_guard_test.go`): the whole set lives in
/// the iOS tunnel extension's memory, and a live reload briefly holds two
/// copies of one file.
const rulesetMaxFileBytes = 1536 * 1024;
const rulesetMaxTotalBytes = 2 * 1024 * 1024;
const rulesetMaxManifestBytes = 64 * 1024;

/// How often a connected client asks the mirror for a newer manifest. The
/// mirror publishes about once a week; asking daily keeps the lag near a day.
const rulesetCheckInterval = Duration(hours: 24);

/// When to try again after the mirror could not be reached or a download
/// broke off.
const rulesetRetryAfterFailure = Duration(hours: 1);

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');

sealed class MirrorDecision {
  const MirrorDecision();
}

/// Nothing newer, or a version rejected before. Not worth a log line.
class MirrorUpToDate extends MirrorDecision {
  const MirrorUpToDate(this.why);
  final String why;
}

/// The manifest cannot be for this build, or breaks a cap.
class MirrorRefused extends MirrorDecision {
  const MirrorRefused(this.why);
  final String why;
}

/// Newer and well-formed: fetch [files], the ones whose digest differs from
/// the installed copy.
class MirrorDownload extends MirrorDecision {
  const MirrorDownload(this.files);
  final List<RulesetManifestFile> files;
}

/// What to do with a manifest from the mirror, decided before downloading
/// anything. The store checks the bytes again against the bundle before it
/// installs them.
MirrorDecision mirrorDecision(
  RulesetManifest remote, {
  required RulesetManifest installed,
  required Set<String> rejected,
}) {
  final time = remote.versionTime;
  if (time == null) return const MirrorRefused('unreadable version');
  if (remote.schema != kRulesetSchema) {
    return MirrorRefused('schema ${remote.schema}, this build loads $kRulesetSchema');
  }
  final names = remote.fileNames;
  if (names.length != remote.files.length) return const MirrorRefused('a file is listed twice');
  if (names.length != installed.fileNames.length || !names.containsAll(installed.fileNames)) {
    return const MirrorRefused("file list differs from this build's");
  }
  if (rejected.contains(remote.version)) return const MirrorUpToDate('rejected before');
  final installedTime = installed.versionTime;
  if (installedTime != null && !time.isAfter(installedTime)) return const MirrorUpToDate('nothing newer');

  var total = 0;
  for (final file in remote.files) {
    final size = file.size;
    if (!_sha256Hex.hasMatch(file.sha256)) return MirrorRefused('${file.name} has a malformed digest');
    if (size == null || size <= 0) return MirrorRefused('${file.name} has no size');
    if (size > rulesetMaxFileBytes) return MirrorRefused('${file.name} is $size bytes, over the cap');
    total += size;
  }
  if (total > rulesetMaxTotalBytes) return MirrorRefused('the set is $total bytes, over the cap');

  final installedDigests = {for (final file in installed.files) file.name: file.sha256.toLowerCase()};
  return MirrorDownload([
    for (final file in remote.files)
      if (installedDigests[file.name] != file.sha256) file,
  ]);
}

typedef MirrorFetch = Future<Uint8List> Function(String url, int maxBytes);

/// One pass against the mirror: check the manifest, download what changed,
/// hand it to the store. Returns how long to wait before the next pass.
///
/// The last check time is recorded only when the mirror answered with
/// something definite (up to date, refused, installed, staged). A network
/// failure leaves it alone and retries within the hour.
class RulesetUpdate {
  RulesetUpdate({required this.store, required this.fetch, required this.base, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final RulesetStore store;
  final MirrorFetch fetch;

  /// The mirror's base URL, without a trailing slash. Paths below it carry
  /// the schema, so a build only ever reads the files its core expects.
  final String base;
  final DateTime Function() _clock;

  static final _log = Loggy('ruleset_update');

  String get _root => '$base/v$kRulesetSchema';

  Future<Duration> run() async {
    final now = _clock();
    final state = await store.readState();
    final last = state.lastCheck;
    if (last != null) {
      final since = now.difference(last);
      if (!since.isNegative && since < rulesetCheckInterval) return rulesetCheckInterval - since;
    }

    final installed = await store.installedManifest();
    if (installed == null) {
      _log.warning('no installed rule-sets to compare against; skipping the mirror');
      return rulesetRetryAfterFailure;
    }

    final RulesetManifest remote;
    try {
      final bytes = await fetch('$_root/MANIFEST', rulesetMaxManifestBytes);
      remote = RulesetManifest.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);
    } catch (e) {
      _log.info('rule-set mirror: manifest unavailable (${describeMirrorError(e)})');
      return rulesetRetryAfterFailure;
    }

    final decision = mirrorDecision(remote, installed: installed, rejected: state.rejected.toSet());
    switch (decision) {
      case MirrorUpToDate(:final why):
        _log.debug('rule-set mirror: $why (${installed.version})');
        await store.recordCheck(now);
        return rulesetCheckInterval;
      case MirrorRefused(:final why):
        _log.warning('rule-set mirror: ${remote.version} refused: $why');
        await store.recordCheck(now);
        return rulesetCheckInterval;
      case MirrorDownload(:final files):
        _log.info('rule-set mirror: ${remote.version} available, ${files.length} files to fetch');
        final changed = <String, List<int>>{};
        for (final file in files) {
          final Uint8List bytes;
          try {
            bytes = await fetch('$_root/files/${file.sha256}.srs', file.size!);
          } catch (e) {
            _log.info('rule-set mirror: ${file.name} unavailable (${describeMirrorError(e)})');
            return rulesetRetryAfterFailure;
          }
          final problem = bytes.length != file.size
              ? '${bytes.length} bytes, expected ${file.size}'
              : sha256.convert(bytes).toString() != file.sha256
              ? 'does not match its digest'
              : srsProblem(bytes);
          if (problem != null) {
            _log.warning('rule-set mirror: ${remote.version} refused: ${file.name} $problem');
            await store.recordCheck(now);
            return rulesetCheckInterval;
          }
          changed[file.name] = bytes;
        }
        final result = await store.installDownloaded(remote, changed);
        _log.info('rule-set mirror: ${remote.version} $result');
        await store.recordCheck(now);
        return rulesetCheckInterval;
    }
  }
}

/// A failure, named by kind only: a URL or a server message in a log that a
/// user might share says more than the kind does, and the kind is what tells
/// a dead tunnel from a broken mirror.
String describeMirrorError(Object error) => switch (error) {
  DioException(:final type, :final response) =>
    response?.statusCode != null ? 'HTTP ${response!.statusCode}' : type.name,
  ResponseTooLargeException() => error.toString(),
  FormatException() => 'unreadable manifest',
  _ => error.runtimeType.toString(),
};

/// Runs [check] while connected: once after [firstDelay] when the connection
/// comes up, then again after whatever delay each run returns, until it goes
/// down. Disconnecting cancels the wait and calls [onStop], which aborts a run
/// in flight; a run that finishes after the disconnect schedules nothing.
class ConnectedLoop {
  ConnectedLoop({required this.check, required this.firstDelay, this.onStop});

  final Future<Duration> Function() check;
  final Duration Function() firstDelay;
  final void Function()? onStop;

  Timer? _timer;
  var _connected = false;

  void connected(bool value) {
    if (value == _connected) return;
    _connected = value;
    if (value) {
      _schedule(firstDelay());
    } else {
      stop();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    onStop?.call();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _fire);
  }

  Future<void> _fire() async {
    _timer = null;
    if (!_connected) return;
    Duration next;
    try {
      next = await check();
    } catch (_) {
      next = rulesetRetryAfterFailure;
    }
    if (_connected && _timer == null) _schedule(next);
  }
}

/// Keeps the rule-sets fresh from the Rayn mirror while the app is connected.
///
/// Downloads go only through the tunnel (`proxyOnly`), never direct: the
/// rule-sets only act on a connection, the request then reveals nothing to the
/// local network, and inside a censored network the mirror may not be
/// reachable any other way. A download that lands is renamed into place and
/// the core reloads it live; see [RulesetStore].
///
/// Off when [Constants.rulesetMirrorBase] is empty. Eager-started from
/// `App.build` once a profile exists.
@Riverpod(keepAlive: true)
class RulesetUpdater extends _$RulesetUpdater {
  ConnectedLoop? _loop;
  CancelToken? _inFlight;

  @override
  void build() {
    final base = Constants.rulesetMirrorBase;
    if (base.isEmpty) return;
    final random = Random();
    final loop = ConnectedLoop(
      check: () => _check(base),
      // 30 s to 2 min: lets the core finish starting (and Go close the files
      // it opened, which on Windows otherwise refuse a rename), and spreads a
      // crowd that reconnects together after an outage.
      firstDelay: () => Duration(seconds: 30 + random.nextInt(91)),
      onStop: () => _inFlight?.cancel(),
    );
    _loop = loop;
    ref.onDispose(loop.stop);
    ref.listen(connectionNotifierProvider, (_, next) {
      loop.connected(next.valueOrNull?.isConnected ?? false);
    }, fireImmediately: true);
  }

  Future<Duration> _check(String base) async {
    final dirs = await ref.read(appDirectoriesProvider.future);
    final client = ref.read(httpClientProvider);
    final token = _inFlight = CancelToken();
    try {
      return await RulesetUpdate(
        store: RulesetStore(dirs.workingDir),
        base: base,
        fetch: (url, maxBytes) => client.getBytes(url, maxBytes: maxBytes, proxyOnly: true, cancelToken: token),
      ).run();
    } finally {
      if (identical(_inFlight, token)) _inFlight = null;
    }
  }

  @visibleForTesting
  ConnectedLoop? get loop => _loop;
}
