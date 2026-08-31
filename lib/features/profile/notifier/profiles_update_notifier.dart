import 'dart:async';

import 'package:dartx/dartx.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/notifications/data/notification_data_providers.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/config_slot.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/features/profile/model/hub_tier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:meta/meta.dart';
import 'package:neat_periodic_task/neat_periodic_task.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'profiles_update_notifier.g.dart';

typedef ProfileUpdateStatus = ({String name, bool success});

@Riverpod(keepAlive: true)
class ForegroundProfilesUpdateNotifier extends _$ForegroundProfilesUpdateNotifier with AppLogger {
  static const prefKey = "profiles_update_check";
  static const interval = Duration(minutes: 15);

  @override
  Stream<ProfileUpdateStatus?> build() {
    var cycleCount = 0;
    _scheduler = NeatPeriodicTaskScheduler(
      name: 'profiles update worker',
      interval: interval,
      timeout: const Duration(minutes: 5),
      task: () async {
        loggy.debug("cycle [${cycleCount++}]");
        await updateProfiles();
      },
    );

    ref.onDispose(() async {
      await _scheduler?.stop();
      _scheduler = null;
      await _urlTestSub?.cancel();
      _urlTestSub = null;
    });

    // The fast path. The core URL-tests every exit with a 5 s timeout and
    // pushes the result over a stream the app is already consuming, so a
    // blocked hub is visible within seconds — the same signal that turns the
    // latency pill red. The refresh-cycle ladder below stays as the backstop:
    // it survives the app being backgrounded, where this stream is cancelled,
    // and it tests the middleware rather than one connection-test host.
    _urlTestSub = ref
        .read(proxyRepositoryProvider)
        .watchActiveProxies()
        .listen(
          (event) => event.fold(
            (_) => _allTimedOutSince = null,
            _onOutboundDelays,
          ),
          onError: (_) => _allTimedOutSince = null,
        );

    // Only run the auto-update scheduler when the user has authenticated
    // (i.e. a profile exists). Pre-auth there's nothing to refresh.
    if (ref.watch(hasAnyProfileProvider).valueOrNull ?? false) {
      loggy.debug("authenticated, starting profile auto-update");
      _scheduler?.start();
    } else {
      loggy.debug("not authenticated, skipping profile auto-update");
    }
    return const Stream.empty();
  }

  NeatPeriodicTaskScheduler? _scheduler;
  bool _forceNextRun = false;

  StreamSubscription<Either<ProxyFailure, List<OutboundGroup>>>? _urlTestSub;

  /// When every exit first reported a timed-out URL test, or null if any of
  /// them is currently healthy or still untested. In memory only: it describes
  /// a live core session and means nothing across a restart.
  DateTime? _allTimedOutSince;

  /// Guards `_failOverToStandby` against two callers at once. The refresh-cycle
  /// ladder and the URL-test watcher can now both reach it, and a failover is a
  /// core restart plus a slot write — running two concurrently would interleave
  /// the preference writes with the restart they describe.
  bool _failoverInFlight = false;

  /// Reacts to the core's per-exit URL-test results.
  ///
  /// Every exit dials the same hub, so all of them timing out says the hub is
  /// not carrying traffic. It does NOT say the hub is to blame — an offline
  /// device looks identical — which is why this ends in the same
  /// `_failOverToStandby` whose post-switch probe reverts when the standby hub
  /// is equally dead.
  void _onOutboundDelays(List<OutboundGroup> groups) {
    final delays = groups
        .expand((group) => group.items)
        .where((item) => !item.tag.contains('§hide§'))
        .map((item) => item.urlTestDelay);

    if (!allExitsTimedOut(delays)) {
      _allTimedOutSince = null;
      return;
    }

    final now = DateTime.now();
    final since = _allTimedOutSince;
    // Re-stamp on a first sighting, and on a clock that moved backwards — see
    // urlTestFailureConfirmed.
    if (since == null || now.isBefore(since)) {
      _allTimedOutSince = now;
      return;
    }
    if (!urlTestFailureConfirmed(since, now)) return;

    _allTimedOutSince = null;
    unawaited(_failOverOnUrlTestFailure());
  }

  /// The fast path's preconditions, which are the ladder's own.
  ///
  /// Deliberately does NOT record a check. `checks` is documented to the
  /// middleware as one verdict per refresh interval, and its magnitude is used
  /// there as a proxy for how long the client was observing; feeding a second,
  /// far faster measurement source into the same counter would quietly break
  /// that. The `unreachable` edge marker still goes out, from inside
  /// `_failOverToStandby`.
  Future<void> _failOverOnUrlTestFailure() async {
    if (_failoverInFlight) return;
    if (ref.read(connectionNotifierProvider).valueOrNull is! Connected) return;

    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    if (configSlotOf(prefs.getString(activeConfigSlotKey)) != ConfigSlot.primary) return;
    if (!failoverAttemptDue(DateTime.tryParse(prefs.getString(hubOfflineBackoffKey) ?? ""), DateTime.now())) {
      return;
    }

    final profile = await ref.read(activeProfileProvider.future);
    if (profile is! RemoteProfileEntity) return;
    if (await _currentTier(profile.id) != HubTier.primary) return;

    loggy.warning(
      "every exit timed out its URL test for ${hubUrlTestWindow.inSeconds}s; treating the primary hub as blocked",
    );
    await _failOverToStandby(profile);
  }

  Future<void> trigger() async {
    loggy.debug("triggering update");
    _forceNextRun = true;
    await _scheduler?.trigger();
  }

  @visibleForTesting
  Future<void> updateProfiles() async {
    var force = false;
    if (_forceNextRun) {
      force = true;
      _forceNextRun = false;
    }

    try {
      final previousRun = DateTime.tryParse(ref.read(sharedPreferencesProvider).requireValue.getString(prefKey) ?? "");

      if (!force && previousRun != null && previousRun.add(interval) > DateTime.now()) {
        loggy.debug("too soon! previous run: [$previousRun]");
        return;
      }
      loggy.debug("${force ? "[FORCED] " : ""}running, previous run: [$previousRun]");

      final remoteProfiles = await ref
          .read(profileRepositoryProvider)
          .requireValue
          .watchAll()
          .map(
            (event) => event.getOrElse((f) {
              loggy.error("error getting profiles");
              throw f;
            }).whereType<RemoteProfileEntity>(),
          )
          .first;

      await for (final profile in Stream.fromIterable(remoteProfiles)) {
        final updateInterval = profile.options?.updateInterval;
        if (force || updateInterval != null && updateInterval <= DateTime.now().difference(profile.lastUpdate)) {
          final t = ref.read(translationsProvider).requireValue;
          final result = await _refreshCarryingCounters(profile.url);
          await result.fold(
            (l) async {
              if (l is ProfileSubscriptionExpiredFailure) {
                // Lapsed subscription: notify (deduped) and keep the last
                // config. The backend disables the tunnel server-side at
                // expiry, so the client does not disconnect. A later renewal
                // returns a `new-url` and auto-migrates.
                loggy.info("profile [${profile.id}] subscription expired with no renewal");
                await _raiseSubscriptionExpired();
                state = AsyncData((name: profile.name, success: false));
              } else {
                loggy.debug("error updating profile [${profile.id}]", l);
                ref
                    .read(inAppNotificationControllerProvider)
                    .showErrorToast(t.pages.profiles.msg.update.failureNamed(name: profile.name));
                state = AsyncData((name: profile.name, success: false));
                // A refresh that failed WHILE CONNECTED is not noise — it is the
                // primary symptom of a blocked hub on iOS and desktop, where the
                // app's own traffic is captured by the tun and therefore dies
                // with the tunnel. Running the ladder only on success would have
                // confined this whole feature to Android, which is the one
                // platform that never needed it.
                //
                // Last, so the UI settles before a sequence that takes a minute.
                await _checkHubReachability(profile);
              }
            },
            (_) async {
              loggy.debug("profile [${profile.id}] updated successfully");
              // Before the reachability check, which can block for the length of
              // its confirmation delay: a failover is worth nothing without a
              // cache to fail over to.
              await _refreshStandbyCacheIfDue(profile);
              await _checkHubReachability(profile);
              // A good config returned — clear any standing "expired" prompt.
              await _clearSubscriptionExpired();
              ref
                  .read(inAppNotificationControllerProvider)
                  .showSuccessToast(t.pages.profiles.msg.update.success);
              state = AsyncData((name: profile.name, success: true));
            },
          );
        } else {
          loggy.debug(
            "skipping profile [${profile.id}] update. last successful update: [${profile.lastUpdate}] - interval: [${profile.options?.updateInterval}]",
          );
        }
      }
    } finally {
      await ref.read(sharedPreferencesProvider).requireValue.setString(prefKey, DateTime.now().toIso8601String());
    }
  }

  /// Keeps the precached standby config fresh.
  ///
  /// Runs only after a SUCCESSFUL primary refresh, and that is what makes the
  /// cadence self-limiting: a device that cannot reach the middleware never
  /// spends requests discovering it again, and a device that can costs one
  /// extra request a day.
  ///
  /// Failures are logged and swallowed. The standby config is an optimisation
  /// the client keeps for itself; the subscription it belongs to just refreshed
  /// successfully, so there is nothing here for the user to act on and a toast
  /// would only report an internal detail they cannot influence.
  Future<void> _refreshStandbyCacheIfDue(RemoteProfileEntity profile) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final due = standbyRefreshDue(
      DateTime.tryParse(prefs.getString(standbyCachedAtKey) ?? ""),
      DateTime.tryParse(prefs.getString(standbyAttemptedAtKey) ?? ""),
      DateTime.now(),
    );
    if (!due) return;

    // Stamped BEFORE the attempt, so a fetch that hangs or throws still backs
    // off. Recording it afterwards would leave a crash loop retrying forever.
    await prefs.setString(standbyAttemptedAtKey, DateTime.now().toIso8601String());
    loggy.debug("standby config cache is due; fetching");

    final result = await ref.read(profileRepositoryProvider).requireValue.refreshStandbyConfig(profile).run();
    final failure = result.fold<ProfileFailure?>((l) => l, (_) => null);
    if (failure != null) {
      loggy.info("standby config refresh failed (${failure.runtimeType}); keeping any previous cache");
      return;
    }
    await prefs.setString(standbyCachedAtKey, DateTime.now().toIso8601String());
    loggy.debug("standby config cached");
  }

  /// The reachability ladder: detect a dead primary hub, fail over to the
  /// precached standby config, and come back when there is reason to.
  ///
  /// Runs after EVERY refresh attempt, successful or not, while connected.
  ///
  /// Both outcomes are informative and neither is conclusive on its own. A
  /// refresh that succeeded may still have been rescued by a direct fallback
  /// around a dead tunnel; a refresh that failed may mean a blocked hub or a
  /// device with no connectivity at all. The ladder does not try to tell those
  /// apart from the refresh result — it probes, and then switches to find out.
  ///
  /// The switch itself is the discriminator, and that is what makes this work
  /// on every platform. An earlier design proved "the hub is dead, not the
  /// device" by fetching once through the tunnel and once around it; but the
  /// app's traffic only escapes the tun on Android, so on iOS and desktop both
  /// legs died together and nothing was ever detected. Here the client just
  /// switches hubs and looks again: if traffic flows, the hub was the problem;
  /// if it does not, the device was offline and we revert. Same discrimination,
  /// obtained by doing the thing we wanted to do anyway.
  Future<void> _checkHubReachability(RemoteProfileEntity profile) async {
    if (ref.read(connectionNotifierProvider).valueOrNull is! Connected) return;
    final prefs = ref.read(sharedPreferencesProvider).requireValue;

    if (configSlotOf(prefs.getString(activeConfigSlotKey)) == ConfigSlot.standby) {
      await _considerReturnToPrimary(profile);
      return;
    }

    // Nothing to observe, and nowhere to go. When a subscriber crosses their
    // rolling allowance the middleware serves the standby hub in the ORDINARY
    // response, so the config in the primary slot already dials it. Probing
    // here would measure the standby hub while counting the result as a primary
    // observation, and a failover would swap that hub for the identical one in
    // the standby slot.
    //
    // Read fresh from the row: the profile this cycle started with predates the
    // refresh that may have just changed the tier.
    if (await _currentTier(profile.id) != HubTier.primary) {
      loggy.debug("middleware is serving the standby tier; no primary hub to observe this cycle");
      return;
    }

    // Checked BEFORE probing, not just before switching: an offline device
    // would otherwise still burn the two probes and the confirmation delay on
    // every cycle to reach the same conclusion.
    if (!failoverAttemptDue(DateTime.tryParse(prefs.getString(hubOfflineBackoffKey) ?? ""), DateTime.now())) {
      loggy.debug("within the post-revert backoff; not probing");
      return;
    }

    if (await _tunnelCarriesTraffic(profile.url)) {
      await _recordCheck(failed: false);
      // Whatever was wrong has cleared; a later failure should get a fresh
      // attempt rather than inherit an old backoff.
      await prefs.remove(hubOfflineBackoffKey);
      return;
    }

    // One probe is a single sample, and a congested link can time a healthy
    // hub's request out. Confirm before restarting anyone's tunnel.
    loggy.info("tunnelled probe failed; confirming in ${hubConfirmDelay.inSeconds}s");
    await Future<void>.delayed(hubConfirmDelay);

    // The connection is re-checked ACROSS the delay, not just at entry. Thirty
    // seconds is long enough for a user to give up on a tunnel that is visibly
    // doing nothing and toggle it — and with the core stopped the confirming
    // probe fails instantly with connection-refused, which reads exactly like a
    // dead hub. That is a false detection built out of the user's own remedy.
    if (ref.read(connectionNotifierProvider).valueOrNull is! Connected) {
      loggy.info("connection changed during the confirmation delay; abandoning this detection");
      return;
    }

    if (await _tunnelCarriesTraffic(profile.url)) {
      // ONE check, not two. The pair of probes reached a single verdict, and it
      // was "carrying" — counting the failed first probe would make a flaky
      // request look like a hub problem, which is what the confirmation exists
      // to distinguish.
      await _recordCheck(failed: false);
      loggy.info("confirming probe succeeded; not failing over");
      return;
    }

    await _recordCheck(failed: true);
    await _failOverToStandby(profile);
  }

  /// Moves this client onto the precached standby config and checks whether
  /// that fixed anything.
  Future<void> _failOverToStandby(RemoteProfileEntity profile) async {
    if (_failoverInFlight) return;
    _failoverInFlight = true;
    try {
      await _failOverToStandbyLocked(profile);
    } finally {
      _failoverInFlight = false;
    }
  }

  Future<void> _failOverToStandbyLocked(RemoteProfileEntity profile) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final repository = ref.read(profileRepositoryProvider).requireValue;
    final now = DateTime.now();
    final flips = recentFlips(prefs.getStringList(hubFlipsKey), now);

    final hasCache = (await repository.readConfig(profile.id, slot: ConfigSlot.standby).run()).isRight();
    // Re-read both rather than assuming: the confirmation delay above is 30s of
    // wall clock, during which a user connect may have moved the slot and a
    // refresh may have moved the tier.
    final slot = configSlotOf(prefs.getString(activeConfigSlotKey));
    final servedTier = await _currentTier(profile.id);
    if (!failoverAllowed(
      slot: slot,
      servedTier: servedTier,
      hasStandbyCache: hasCache,
      recentFlipCount: flips.length,
    )) {
      // Staying put is the right answer here. A client with no usable standby
      // config is better off on a dead primary it can still refresh from than
      // restarted onto nothing, and one that has already flapped its way
      // through the cap is telling us the switching is the problem.
      loggy.warning(
        "primary hub is not carrying traffic but failover is not available "
        "(slot: ${slot.name}, served tier: ${servedTier.name}, standby cached: $hasCache, "
        "flips in window: ${flips.length})",
      );
      return;
    }

    // Remember which primary we are leaving, so a later refresh can notice the
    // operator moved it — the fastest signal that the block was answered.
    final primaryConfig = (await repository.readConfig(profile.id).run()).toNullable();
    final digest = primaryConfig == null ? null : hubDigest(primaryConfig);

    loggy.warning("primary hub is not carrying traffic; switching to the standby hub");
    await prefs.setString(activeConfigSlotKey, ConfigSlot.standby.name);
    await prefs.setString(hubStandbySinceKey, now.toIso8601String());
    if (digest != null) {
      await prefs.setString(hubPrimaryDigestKey, digest);
      await prefs.setString(hubPrimaryTierKey, (await _currentTier(profile.id)).name);
    } else {
      // No fingerprint means the early-return path has nothing to compare, so
      // this leg will run to its full lease. Worth a line when someone asks why.
      await prefs.remove(hubPrimaryDigestKey);
      await prefs.remove(hubPrimaryTierKey);
      loggy.info("could not fingerprint the primary config; this standby leg will run to its lease");
    }

    if (!await ref.read(connectionNotifierProvider.notifier).restartForSlot(profile)) {
      loggy.error("could not restart onto the standby hub; reverting");
      await _returnToPrimary(profile, restart: false);
      return;
    }

    // Recorded HERE, not before the restart. The flap cap exists to bound how
    // often the core is torn down and every live connection dropped, so it must
    // count switches that happened — not intentions. `restartForSlot` refuses
    // while disconnected, which is exactly the case a user toggling mid-
    // detection produces, and charging them for it would let four such toggles
    // suppress genuine failover for a day while the log claimed four flips the
    // client never made.
    await prefs.setStringList(hubFlipsKey, [
      ...flips.map((at) => at.toIso8601String()),
      now.toIso8601String(),
    ]);

    if (await _tunnelCarriesTraffic(profile.url)) {
      loggy.warning("the standby hub carries traffic; the primary hub was the problem");
      await _report(profile, HubSignal.unreachable);
      return;
    }

    // Neither hub works, so the fault was never the hub. Go back rather than
    // leave someone parked on the inferior link for a lease they did not earn,
    // and back off before spending two more core restarts on the same answer.
    loggy.info("the standby hub does not carry traffic either; the device is offline, reverting");
    await prefs.setString(hubOfflineBackoffKey, DateTime.now().toIso8601String());
    await _returnToPrimary(profile);
  }

  /// While on a forced standby leg, decides whether to go back.
  ///
  /// Two triggers, cheapest first. The digest check is the one that usually
  /// fires: the operator rotates a blocked hub's address, the standby tunnel
  /// carries the refresh that delivers the new one, and the client returns
  /// immediately instead of waiting out a lease for a hub that has already
  /// moved. The lease is the fallback for a block being ridden out in place.
  Future<void> _considerReturnToPrimary(RemoteProfileEntity profile) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final stored = prefs.getString(hubPrimaryDigestKey);
    final currentConfig = (await ref.read(profileRepositoryProvider).requireValue.readConfig(profile.id).run())
        .toNullable();
    final current = currentConfig == null ? null : hubDigest(currentConfig);

    if (primaryHubMoved(
      storedDigest: stored,
      currentDigest: current,
      storedTier: hubTierOf(prefs.getString(hubPrimaryTierKey)),
      currentTier: await _currentTier(profile.id),
    )) {
      loggy.info("the primary hub's address changed while we were on standby; returning to it");
      await _returnToPrimary(profile);
      return;
    }

    if (standbyLeaseExpired(DateTime.tryParse(prefs.getString(hubStandbySinceKey) ?? ""), DateTime.now())) {
      loggy.info("standby lease expired; returning to the primary hub to retest it");
      await _returnToPrimary(profile);
    }
  }

  /// Clears the forced standby leg and puts the core back on the primary config.
  ///
  /// [restart] is false only when the core is already down, in which case there
  /// is nothing to restart and the next connect will read the cleared slot.
  Future<void> _returnToPrimary(RemoteProfileEntity profile, {bool restart = true}) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    await prefs.remove(activeConfigSlotKey);
    await prefs.remove(hubStandbySinceKey);
    await prefs.remove(hubPrimaryDigestKey);
    await prefs.remove(hubPrimaryTierKey);
    if (!restart) return;
    if (!await ref.read(connectionNotifierProvider.notifier).restartForSlot(profile)) return;
    // A verdict about the primary hub like any other, and one of the few this
    // client gets while a block persists: every other check is suppressed on a
    // standby leg.
    final carrying = await _tunnelCarriesTraffic(profile.url);
    await _recordCheck(failed: !carrying);
    // Only worth telling the middleware once we know the primary works again.
    if (carrying) await _report(profile, HubSignal.recovered);
  }

  /// Tells the middleware what we observed, over the tunnel that works.
  ///
  /// Informational only — the switch has already happened. It is aggregated per
  /// cohort so that many reports from one cohort become an ops alert, so a
  /// single client failing to deliver one costs nothing and must never be
  /// allowed to affect what this client does next.
  Future<void> _report(RemoteProfileEntity profile, HubSignal signal) async {
    final result = await _refreshCarryingCounters(profile.url, signal: signal);
    if (result.isLeft()) loggy.info("could not deliver the [${signal.wireValue}] report; it will be re-sent");
  }

  /// The quota tier as of RIGHT NOW, read from the row rather than from the
  /// profile this cycle started with.
  ///
  /// That distinction is load-bearing. The `profile` threaded through this
  /// notifier is the snapshot taken before `upsertRemote` ran, so its headers
  /// are one refresh behind — while the config file the fingerprint is taken
  /// from has just been rewritten. Comparing a stale tier against a fresh
  /// digest would report "tier unchanged" on precisely the cycle a quota move
  /// changed the address, which is the one cycle the guard in
  /// [primaryHubMoved] exists to catch.
  Future<HubTier> _currentTier(String profileId) async {
    final fresh = (await ref.read(profileRepositoryProvider).requireValue.getById(profileId).run()).toNullable();
    return hubTierOf(subscriptionHeader(fresh, 'subscription-hub-tier'));
  }

  /// Records one verdict about the primary hub.
  ///
  /// Counts VERDICTS, not HTTP probes. A confirmed detection makes two probes
  /// and reaches one conclusion; counting probes would halve the failure rate
  /// of a fully blocked client and make the number impossible to reason about
  /// without knowing the ladder's internals.
  ///
  /// Deliberately not called for the probe taken immediately after switching to
  /// standby: that one tests the OTHER hub, and belongs in neither the
  /// numerator nor the denominator.
  Future<void> _recordCheck({required bool failed}) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    await prefs.setInt(hubChecksKey, bumpCounter(prefs.getInt(hubChecksKey) ?? 0));
    if (failed) {
      await prefs.setInt(hubFailuresKey, bumpCounter(prefs.getInt(hubFailuresKey) ?? 0));
    }
  }

  /// A subscription refresh that also delivers the observation window.
  ///
  /// Snapshot, send, and subtract only what was sent — and only on success.
  ///
  /// Both halves of that matter. Subtracting rather than zeroing preserves a
  /// check that landed while the request was in flight. Clearing only on
  /// success is the entire reason these are counters: on iOS and desktop a
  /// blocked hub fails the refresh itself, so the window stays open across
  /// however many cycles it takes for a failover to restore a working tunnel,
  /// and the backlog then goes out in one report.
  Future<Either<ProfileFailure, Unit>> _refreshCarryingCounters(String url, {HubSignal? signal}) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final sent = (checks: prefs.getInt(hubChecksKey) ?? 0, failures: prefs.getInt(hubFailuresKey) ?? 0);

    final result = await ref
        .read(profileRepositoryProvider)
        .requireValue
        .upsertRemote(url, signal: signal, counters: sent)
        .run();

    if (result.isRight() && sent.checks > 0) {
      await prefs.setInt(hubChecksKey, settleCounter(prefs.getInt(hubChecksKey) ?? 0, sent.checks));
      await prefs.setInt(hubFailuresKey, settleCounter(prefs.getInt(hubFailuresKey) ?? 0, sent.failures));
    }
    return result;
  }

  /// One tunnelled fetch: does the hub carry traffic?
  ///
  /// Single-leg by design. `proxyOnly` pins it to the core, so a failure is a
  /// statement about the tunnel and nothing else — the ordinary `both` mode
  /// would silently fall through to a direct connection and report success for
  /// a completely dead hub.
  ///
  /// Every exit in a profile is VLESS to the SAME hub address, differentiated
  /// only by the route code in its UUID, so one fetch is a fair test of the hub
  /// rather than of any single exit.
  Future<bool> _tunnelCarriesTraffic(String url) async {
    try {
      await ref
          .read(httpClientProvider)
          .getText(
            url,
            proxyOnly: true,
            userAgent: ref.read(appInfoProvider).requireValue.subscriptionUserAgent,
          );
      return true;
    } catch (err) {
      loggy.debug("tunnelled probe failed (${err.runtimeType})");
      return false;
    }
  }

  /// Raise a single persistent "subscription expired" notification, deduped so
  /// repeated polls while lapsed don't spam the inbox.
  Future<void> _raiseSubscriptionExpired() async {
    final dao = ref.read(notificationDataSourceProvider);
    if (await dao.hasAnyOfKind(NotificationKind.subscriptionExpired)) return;
    await dao.insert(
      AppNotificationsCompanion.insert(
        id: const Uuid().v4(),
        kind: NotificationKind.subscriptionExpired,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _clearSubscriptionExpired() async {
    await ref.read(notificationDataSourceProvider).deleteByKind(NotificationKind.subscriptionExpired);
  }
}
