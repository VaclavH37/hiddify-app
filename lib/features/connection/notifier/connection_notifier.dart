import 'dart:io';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/model/config_slot.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/features/profile/model/hub_tier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  @override
  Stream<ConnectionStatus> build() async* {
    if (Platform.isIOS) {
      await _connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run();
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      if (previous case AsyncData(:final value) when !value.isConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            // Track successful connections and only ask for a review once the
            // user has connected enough times to have formed an opinion.
            // Google's In-App Review guidance discourages prompting after a
            // first/trivial interaction. Ask at most once, and don't consume
            // the single attempt if the API isn't currently available (it's
            // quota-limited) — retry on a later connection instead.
            final connectionCount = ref.read(Preferences.successfulConnectionCount) + 1;
            await ref.read(Preferences.successfulConnectionCount.notifier).update(connectionCount);
            if (connectionCount >= 3 && await InAppReview.instance.isAvailable()) {
              await InAppReview.instance.requestReview();
              await ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      if (next == null || previous.id != next.id) {
        await reconnect(next);
        return;
      }
      // Same profile, refreshed content. A subscription refresh rewrites
      // `configs/<id>.enc` but does not restart the core, so without this a
      // user who stays connected for days never moves off the tier they
      // started on — exactly the heaviest users the allowance exists to shape.
      await _applyHubTierChange(next);
    });
    ref.watch(coreRestartSignalProvider);

    yield* _connectionRepo.watchConnectionStatus().doOnData((event) {
      if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
        // Deferred to a microtask: this runs inside the connection-status stream,
        // so updating a provider here mutates state during another provider's
        // build phase.
        Future.microtask(() => ref.read(Preferences.startedByUser.notifier).update(false));
      }
      loggy.info("connection status: ${event.format()}");
    });
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  Future<void> mayConnect() async {
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  }

  Future<void> toggleConnection() async {
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (state case AsyncError()) {
      await haptic.lightImpact();
      await _connect();
    } else if (state case AsyncData(:final value)) {
      switch (value) {
        case Disconnected():
          await haptic.lightImpact();
          await ref.read(Preferences.startedByUser.notifier).update(true);
          await _retryPrimaryHubIfDue();
          await _connect();
        case Connected():
          // default:
          await haptic.mediumImpact();
          await ref.read(Preferences.startedByUser.notifier).update(false);
          await _disconnect();
        default:
          loggy.warning("switching status, debounce");
      }
    }
  }

  Future<void> reconnect(ProfileEntity? profile) async {
    if (state case AsyncData(:final value) when value == const Connected()) {
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      loggy.info("active profile changed, reconnecting");
      await ref.read(Preferences.startedByUser.notifier).update(true);
      await _recordAppliedTier(profile);
      await _connectionRepo.reconnect(profile, ref.read(Preferences.disableMemoryLimit)).mapLeft((err) async {
        loggy.warning("error reconnecting", err);
        state = AsyncError(err, StackTrace.current);
        await ref
            .read(dialogNotifierProvider.notifier)
            .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      }).run();
    }
  }

  /// Retry the primary hub on a user-initiated connect.
  ///
  /// A failover moved this client onto the standby hub because the primary was
  /// not carrying traffic. That block may since have cleared, and while on
  /// standby nothing is dialling the primary to find out. A user tapping
  /// Connect is the closest thing to them saying "try again", so take it as one.
  ///
  /// Entirely local, and that is the improvement: both configs are already on
  /// disk, so this clears a preference and returns. No network call sits in
  /// front of a user who has just tapped Connect, and nothing can time out. If
  /// the primary is still blocked the ladder detects it again within one refresh
  /// cycle and fails back over.
  ///
  /// Floored at [hubRetryPrimaryFloor]: without it, a user toggling the VPN
  /// because it is not working would get a broken primary attempt every time.
  Future<void> _retryPrimaryHubIfDue() async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    if (configSlotOf(prefs.getString(activeConfigSlotKey)) != ConfigSlot.standby) return;
    if (!retryPrimaryDue(DateTime.tryParse(prefs.getString(hubStandbySinceKey) ?? ""), DateTime.now())) return;

    loggy.info("user-initiated connect while on the standby hub; retrying the primary");
    await prefs.remove(activeConfigSlotKey);
    await prefs.remove(hubStandbySinceKey);
  }

  /// Restarts the core onto a different config slot.
  ///
  /// A full stop/start rather than [reconnect], and the difference is
  /// load-bearing. `restart` sends only the config CONTENT, so the platform
  /// shell keeps whatever `activeConfigPath` the last `connect` gave it — and a
  /// start the system initiates on its own (quick-settings tile, always-on
  /// VPN, iOS on-demand) reads that path and decrypts the OLD slot. After a
  /// failover that means silently dialling back into the hub we just fled.
  /// `connect` republishes the path, so the platform and the client agree.
  ///
  /// Returns whether the core came back up. A caller that has already committed
  /// slot state needs to know, because a failed start leaves the client
  /// disconnected with a preference claiming otherwise.
  Future<bool> restartForSlot(ProfileEntity profile) async {
    if (state.valueOrNull is! Connected) return false;
    await _disconnect();
    await _recordAppliedTier(profile);
    final result = await _connectionRepo.connect(profile, ref.read(Preferences.disableMemoryLimit)).run();
    return result.fold((err) {
      loggy.error("failed to restart the core onto the new config slot", err);
      return false;
    }, (_) => true);
  }

  /// The tier the running core was handed, and when we last moved it.
  static const _hubTierAppliedKey = "hub_tier_applied";
  static const _hubTierSwitchKey = "hub_tier_last_switch";

  /// Records the tier the core is about to be started with.
  ///
  /// Persisted rather than held in memory because on Android the background
  /// core outlives the UI: after a relaunch this is the only record of what it
  /// is actually running, and without it a tier change that landed while the
  /// app was dead would never be applied — leaving exactly the always-on heavy
  /// users the allowance exists to shape on the primary link indefinitely.
  ///
  /// Written before the attempt, not after. A failed connect leaves a value
  /// describing a core that is not running, which nothing reads:
  /// [_applyHubTierChange] acts only while connected.
  Future<void> _recordAppliedTier(ProfileEntity? profile) async {
    if (profile == null) return;
    final tier = hubTierOf(subscriptionHeader(profile, 'subscription-hub-tier'));
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    await prefs.setString(_hubTierAppliedKey, tier.name);
  }

  /// Applies a middleware-decided hub-tier change to the running core.
  ///
  /// Does nothing while disconnected: the next connect reads the stored config
  /// and records the tier itself, so there is nothing to restart and nothing to
  /// tell the user about yet.
  Future<void> _applyHubTierChange(ProfileEntity profile) async {
    if (state.valueOrNull is! Connected) return;
    final tier = hubTierOf(subscriptionHeader(profile, 'subscription-hub-tier'));
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    // Compared against what the CORE holds, not against the previous
    // observation: a switch the dwell floor deferred leaves the core where it
    // was, and comparing observations would then treat the flip back as a fresh
    // change and reconnect to the tier already in use.
    final applied = hubTierOf(prefs.getString(_hubTierAppliedKey));
    final now = DateTime.now();
    if (!shouldReconnectForTier(applied, tier, DateTime.tryParse(prefs.getString(_hubTierSwitchKey) ?? ""), now)) {
      if (applied != tier) {
        loggy.info("hub tier is now [${tier.name}], within the dwell floor; deferring to the next connect");
      }
      return;
    }
    loggy.info("hub tier changed [${applied.name}] -> [${tier.name}], reconnecting");
    await prefs.setString(_hubTierSwitchKey, now.toIso8601String());
    // SILENT, deliberately. This used to raise a toast explaining that the
    // full-speed allowance was spent and full speed would return later. The
    // subscriber is not meant to know a tier change happened at all — they get
    // a brief reconnect and a slower link, and no account of why. The log line
    // above is the only record, which is where it belongs.
    await reconnect(profile);
  }

  Future<void> abortConnection() async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting():
          loggy.debug("aborting connection");
          await _disconnect();
        default:
      }
    }
  }

  final _singleStart = SingleCall();

  Future<void> _connect() async {
    _singleStart.run(
      () async {
        await _connectThrottled();
      },
      onIgnored: () {
        loggy.debug("connect called while another connect/disconnect is still running, ignoring");
      },
    );
  }

  Future<void> _connectThrottled() async {
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }
    await _recordAppliedTier(activeProfile);
    await _connectionRepo.connect(activeProfile, ref.read(Preferences.disableMemoryLimit)).mapLeft((
      ConnectionFailure err,
    ) async {
      loggy.warning("error connecting", err);
      //Go err is not normal object to see the go errors are string and need to be dumped
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      loggy.warning(err);
      await ref.read(Preferences.startedByUser.notifier).update(false);
      state = AsyncError(err, StackTrace.current);
    }).run();
  }

  Future<void> _disconnect() async {
    await _connectionRepo.disconnect().mapLeft((err) {
      loggy.warning("error disconnecting", err);
      ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      state = AsyncError(err, StackTrace.current);
    }).run();
  }
}

/// Synchronous on purpose.
///
/// This used to be `Future<bool>` built with `selectAsync`, which meant every
/// consumer had to `await ref.watch(serviceRunningProvider.future)` inside its
/// own build. That `await` suspends the build, so the provider's dependencies
/// are registered *after* the synchronous build phase has finished — and when
/// several siblings on one page do it against a high-frequency stream (the
/// connection status), Riverpod flushes a lazy build in the middle of another
/// one and they collide.
///
/// Reading the already-materialised `AsyncValue` instead keeps the whole thing
/// inside the build phase. `valueOrNull` covers loading and error alike, which
/// is what `.onError(... => false)` was doing.
@Riverpod(keepAlive: true)
bool serviceRunning(Ref ref) {
  // ref.watch(coreRestartSignalProvider);
  return ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
}

class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}
