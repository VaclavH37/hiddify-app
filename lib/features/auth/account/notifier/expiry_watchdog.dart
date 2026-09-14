import 'dart:async';

import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'expiry_watchdog.g.dart';

/// Margin after the stored expiry before asking the Worker, so a refresh that
/// lands a second early does not read "still active" and go quiet until the
/// next poll.
const expiryGrace = Duration(seconds: 30);

/// How far ahead a timer is armed. Anything later is re-evaluated on the next
/// active-profile emission (every persisted refresh) or on resume.
const expiryHorizon = Duration(hours: 48);

/// An expiry more than a year out is the parser's "no expiry" sentinel.
bool isNonExpiring(DateTime expire, DateTime now) => expire.difference(now).inDays > 365;

/// Whether the stored expiry has passed without the Worker having answered
/// since: the last persisted config predates it and no verdict is on file.
bool expiryRefreshDue({
  required DateTime expire,
  required DateTime lastUpdate,
  required DateTime now,
  required bool accountActive,
}) => accountActive && !expire.add(expiryGrace).isAfter(now) && lastUpdate.isBefore(expire);

/// Delay until the expiry check should fire, or null when it is already due
/// (the caller checks now) or further out than [expiryHorizon].
Duration? expiryTimerDelay({required DateTime expire, required DateTime now}) {
  final fireAt = expire.add(expiryGrace);
  if (!fireAt.isAfter(now)) return null;
  final delay = fireAt.difference(now);
  return delay > expiryHorizon ? null : delay;
}

/// Forces a subscription refresh the moment the stored expiry passes.
///
/// `subscription-userinfo`'s `expire=` is the account expiry, and the Worker
/// polls at `profile-update-interval` (12 h in production), so without this
/// the app could show "Tap to connect" for most of a day after the plan ended.
/// The refresh, not the clock, decides the state: a renewal that already
/// landed server-side simply comes back as a config.
///
/// Eager-started from `App.build` once a profile exists; `check` is also
/// called on resume, because a timer does not fire while the app is suspended.
@Riverpod(keepAlive: true)
class ExpiryWatchdog extends _$ExpiryWatchdog with AppLogger {
  Timer? _timer;

  @override
  void build() {
    ref.onDispose(_cancel);
    ref.listen(activeProfileProvider, (_, next) {
      if (next is AsyncData<ProfileEntity?>) _arm(next.value);
    });
    _arm(ref.read(activeProfileProvider).valueOrNull);
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void _arm(ProfileEntity? profile) {
    _cancel();
    if (profile is! RemoteProfileEntity) return;
    final expire = profile.subInfo?.expire;
    if (expire == null) return;
    final now = DateTime.now();
    if (isNonExpiring(expire, now)) return;
    if (_due(profile, now)) {
      _refresh();
      return;
    }
    final delay = expiryTimerDelay(expire: expire, now: now);
    if (delay == null) return;
    loggy.debug("expiry check armed in ${delay.inMinutes} min");
    _timer = Timer(delay, () {
      _timer = null;
      check();
    });
  }

  bool _due(RemoteProfileEntity profile, DateTime now) => expiryRefreshDue(
    expire: profile.subInfo!.expire,
    lastUpdate: profile.lastUpdate,
    now: now,
    accountActive: !ref.read(accountStateNotifierProvider).blocksConnect,
  );

  /// Re-evaluates now: the timer's callback, and every resume.
  void check() {
    final profile = ref.read(activeProfileProvider).valueOrNull;
    if (profile is! RemoteProfileEntity || profile.subInfo == null) return;
    final now = DateTime.now();
    if (isNonExpiring(profile.subInfo!.expire, now)) return;
    if (_due(profile, now)) _refresh();
  }

  void _refresh() {
    loggy.info("stored expiry reached; asking the middleware");
    unawaited(ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger());
  }
}
