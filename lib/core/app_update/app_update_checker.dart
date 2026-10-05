import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/app_update/self_update.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/app_update/update_decision.dart';
import 'package:hiddify/core/app_update/update_install.dart';
import 'package:hiddify/core/app_update/update_keys.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/app_update/update_store.dart';
import 'package:hiddify/core/app_update/widget/app_update_dialog.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/rulesets/ruleset_updater.dart' show describeMirrorError;
import 'package:hiddify/core/utils/connected_loop.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_update_checker.g.dart';

/// How far an install the user started has got.
sealed class UpdateProgress {
  const UpdateProgress();
}

class UpdateDownloading extends UpdateProgress {
  const UpdateDownloading(this.received, this.total);

  final int received;
  final int total;
}

class UpdateVerifying extends UpdateProgress {
  const UpdateVerifying();
}

/// Verified, disconnected and the installer started: the app exits next.
class UpdateInstalling extends UpdateProgress {
  const UpdateInstalling();
}

class UpdateFailed extends UpdateProgress {
  const UpdateFailed(this.reason);

  final UpdateFailure reason;
}

enum UpdateFailure {
  /// The download stopped: the tunnel dropped, the host failed, or the file
  /// ran past its size.
  download,

  /// The file did not match the signed manifest. It has been deleted.
  damaged,

  /// The installer could not be started.
  launch,
}

/// What the About page and the dialog show.
class AppUpdateStatus {
  const AppUpdateStatus({this.offer, this.checking = false, this.progress});

  /// A verified release newer than this build, or null.
  final UpdateManifest? offer;

  /// A check the user started is running.
  final bool checking;

  /// An install the user started, or null.
  final UpdateProgress? progress;

  /// Downloading, verifying or installing: the dialog cannot be closed.
  bool get busy => switch (progress) {
    UpdateDownloading() || UpdateVerifying() || UpdateInstalling() => true,
    _ => false,
  };

  AppUpdateStatus copyWith({UpdateManifest? Function()? offer, bool? checking, UpdateProgress? Function()? progress}) =>
      AppUpdateStatus(
        offer: offer != null ? offer() : this.offer,
        checking: checking ?? this.checking,
        progress: progress != null ? progress() : this.progress,
      );
}

/// Finds newer releases of the Windows EXE build, offers them, and installs
/// one when the user asks.
///
/// Checks run only while connected and fetch only through the tunnel
/// (`proxyOnly`), like the rule-set updater: the first 2 to 5 minutes after
/// the connection comes up, then every [appUpdateCheckInterval]. A release is
/// trusted only once its manifest verifies against the keys pinned in
/// `update_keys.dart`, and its installer only once it matches the size and
/// digest that manifest gives.
///
/// Idle in every build without [kSelfUpdate], and on any platform but an
/// installed Windows build. Eager-started from `App.build` behind the same
/// constant, so other builds compile it out.
@Riverpod(keepAlive: true)
class AppUpdateChecker extends _$AppUpdateChecker {
  static final _log = Loggy('app_update');

  CancelToken? _inFlight;
  CancelToken? _download;
  var _downloadCancelledByUser = false;
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
      final connected = next.valueOrNull?.isConnected ?? false;
      loop.connected(connected);
      // The installer comes only through the tunnel.
      if (!connected) _download?.cancel();
    }, fireImmediately: true);
    unawaited(_startup());
    return const AppUpdateStatus();
  }

  AppUpdateStore get _store => AppUpdateStore(ref.read(sharedPreferencesProvider).requireValue);

  void _setProgress(UpdateProgress? progress) => state = state.copyWith(progress: () => progress);

  Future<int?> _currentBuild() async {
    final info = await ref.read(appInfoProvider.future);
    final build = int.tryParse(info.buildNumber);
    if (build == null || build <= 0) _log.warning('app update: no build number, not checking');
    return build == null || build <= 0 ? null : build;
  }

  /// Settles the update the last run started, clears old downloads, and
  /// restores the offer a previous run found so About shows it at once.
  Future<void> _startup() async {
    final build = await _currentBuild();
    if (build == null) return;
    final dir = updatesDirectory();
    if (clearUpdatesFolder(dir) > 0) {
      // The setup that started this build can still be finishing.
      Timer(const Duration(minutes: 1), () => clearUpdatesFolder(dir));
    }
    await _settleLastAttempt(build);
    final offer = await _store.loadOffer(pinnedKeys: kUpdatePublicKeys, channel: appUpdateChannel, currentBuild: build);
    if (offer != null && state.offer == null) state = state.copyWith(offer: () => offer);
  }

  Future<void> _settleLastAttempt(int currentBuild) async {
    final store = _store;
    final launch = UpdateLaunch.parse(ref.read(launchArgsProvider));
    final outcome = settleUpdateAttempt(
      attemptBuild: store.attemptBuild,
      currentBuild: currentBuild,
      updated: launch.updated,
    );
    if (outcome == UpdateAttemptOutcome.none) return;
    await store.clearAttempt();
    final info = await ref.read(appInfoProvider.future);
    final copy = ref.read(translationsProvider).requireValue.dialogs.appUpdate;
    // The navigator and the toast overlay exist once the first frame is out.
    await SchedulerBinding.instance.endOfFrame;
    switch (outcome) {
      case UpdateAttemptOutcome.installed:
        _log.info('app update: now running ${info.version} (${info.buildNumber})');
        ref.read(inAppNotificationControllerProvider).showSuccessToast(copy.updated(version: info.version));
        if (launch.reconnect) await _reconnectAfterUpdate();
      case UpdateAttemptOutcome.notInstalled:
        _log.warning(
          'app update: the install did not finish; still on ${info.buildNumber} '
          '(Inno Setup log: updates\\$updateLogName)',
        );
        await ref
            .read(dialogNotifierProvider.notifier)
            .showOk(copy.notInstalledTitle, copy.notInstalledBody(version: info.version));
      case UpdateAttemptOutcome.none:
        break;
    }
  }

  /// The app was connected when it left for the update: connect again once
  /// the core reports in, through the same guards as any other connect.
  Future<void> _reconnectAfterUpdate() async {
    try {
      final status = await ref.read(connectionNotifierProvider.future).timeout(const Duration(seconds: 30));
      if (status is! Disconnected) return;
      _log.info('app update: reconnecting after the update');
      await ref.read(connectionNotifierProvider.notifier).mayConnect();
    } catch (e) {
      _log.warning('app update: could not reconnect after the update (${e.runtimeType})');
    }
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
      // An install in progress keeps the offer it is installing.
      if (!state.busy) state = state.copyWith(offer: () => result.offer);
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
    state = state.copyWith(checking: true);
    try {
      final result = await _check(force: true);
      if (result == null) return AppUpdateOutcome.failed;
      if (result.outcome == AppUpdateOutcome.offered) unawaited(showOffer());
      return result.outcome;
    } catch (e) {
      _log.info('app update: manual check failed (${e.runtimeType})');
      return AppUpdateOutcome.failed;
    } finally {
      state = state.copyWith(checking: false);
    }
  }

  /// Puts the pending offer in front of the user. Install runs inside the
  /// dialog, which shows its progress; this acts on Later and Skip.
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
      if (state.progress is UpdateFailed) _setProgress(null);
    }
    if (choice == AppUpdateChoice.skip) {
      _log.info('app update: ${offer.version} (${offer.build}) skipped');
      await _store.skip(offer.build);
    }
  }

  /// Stops a download the user started; the dialog goes back to the offer.
  void cancelDownload() {
    if (_download == null) return;
    _downloadCancelledByUser = true;
    _download?.cancel();
  }

  /// Downloads [offer]'s installer through the tunnel, checks it against the
  /// signed manifest, disconnects, starts it and exits. The installer stops
  /// the app and the tunnel service, replaces the files and starts the new
  /// build (`windows/packaging/exe/inno_setup.sas`), which settles the attempt
  /// at launch.
  Future<void> install(UpdateManifest offer) async {
    if (state.busy) return;
    final dir = updatesDirectory();
    final target = File(p.join(dir.path, installerFileName(offer.installer)));
    final partial = File('${target.path}.part');
    final token = _download = CancelToken();
    _downloadCancelledByUser = false;
    _setProgress(UpdateDownloading(0, offer.installer.size));
    _log.info('app update: downloading ${offer.version} (${offer.build})');
    try {
      dir.createSync(recursive: true);
      for (final stale in [partial, target]) {
        if (stale.existsSync()) stale.deleteSync();
      }
      var shownMb = -1;
      await ref
          .read(httpClientProvider)
          .downloadToFile(
            '$appUpdateBase/${offer.installer.path}',
            partial,
            maxBytes: offer.installer.size,
            proxyOnly: true,
            cancelToken: token,
            onProgress: (received) {
              // A step per megabyte is plenty for the bar.
              final mb = received >> 20;
              if (mb == shownMb) return;
              shownMb = mb;
              _setProgress(UpdateDownloading(received, offer.installer.size));
            },
          );
      partial.renameSync(target.path);
    } catch (e) {
      final cancelled = _downloadCancelledByUser;
      _log.info('app update: download ${cancelled ? 'cancelled' : 'failed (${describeMirrorError(e)})'}');
      _deleteQuietly(partial);
      _setProgress(cancelled ? null : const UpdateFailed(UpdateFailure.download));
      return;
    } finally {
      if (identical(_download, token)) _download = null;
    }

    _setProgress(const UpdateVerifying());
    String? problem;
    try {
      problem = await installerProblem(target, offer.installer);
    } on FileSystemException catch (e) {
      problem = 'unreadable (${e.osError?.errorCode})';
    }
    if (problem != null) {
      _log.warning('app update: downloaded installer refused: $problem');
      _deleteQuietly(target);
      _setProgress(const UpdateFailed(UpdateFailure.damaged));
      return;
    }

    _setProgress(const UpdateInstalling());
    final connection = ref.read(connectionNotifierProvider.notifier);
    final wasConnected = ref.read(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
    await _store.recordAttempt(offer.build);
    // Disconnect first: the installer kills the app and stops the tunnel
    // service within a second or two of starting.
    try {
      await connection.abortConnection().timeout(const Duration(seconds: 5));
    } catch (e) {
      _log.warning('app update: disconnecting before the install failed (${e.runtimeType})');
    }
    try {
      // The app runs elevated, so the installer does too, without a prompt.
      await Process.start(
        target.path,
        installerArguments(reconnect: wasConnected, logPath: p.join(dir.path, updateLogName)),
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      _log.warning('app update: the installer did not start (${e.runtimeType})');
      await _store.clearAttempt();
      _setProgress(const UpdateFailed(UpdateFailure.launch));
      if (wasConnected) await connection.mayConnect();
      return;
    }
    _log.info('app update: installer started for ${offer.version} (${offer.build}); exiting');
    await ref.read(windowNotifierProvider.notifier).exit();
  }

  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Cleared at the next launch.
    }
  }
}
