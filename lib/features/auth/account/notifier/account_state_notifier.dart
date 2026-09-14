import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/auth/account/data/account_state_store.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_state_notifier.g.dart';

@Riverpod(keepAlive: true)
AccountStateStore accountStateStore(Ref ref) => AccountStateStore(ref.watch(sharedPreferencesProvider).requireValue);

/// The one place the account verdict changes. The refresh loop and the in-app
/// renewal report outcomes here; the home page, the connect guard, the
/// redirect and Settings read the result.
///
/// Follows the active profile: a different profile (re-import) or none at all
/// (logout) resets to [AccountActive], because the stored verdict is keyed by
/// profile id and means nothing for another account.
@Riverpod(keepAlive: true)
class AccountStateNotifier extends _$AccountStateNotifier with AppLogger {
  AccountStateStore get _store => ref.read(accountStateStoreProvider);

  @override
  AccountState build() {
    ref.listen(activeProfileProvider, (_, next) {
      // Only a settled value means anything; a loading stream is not a logout.
      if (next is! AsyncData<ProfileEntity?>) return;
      final stored = _stateFor(next.value);
      if (stored != state) state = stored;
    });
    return _stateFor(ref.read(activeProfileProvider).valueOrNull);
  }

  AccountState _stateFor(ProfileEntity? profile) =>
      profile == null ? const AccountActive() : _store.read(profileId: profile.id);

  String? get _profileId => ref.read(activeProfileProvider).valueOrNull?.id;

  /// Records the verdict a refresh returned. Anything that is not an account
  /// verdict — a network failure, a transient `SUBSCRIPTION_UNAVAILABLE`, a
  /// bad config — leaves the state alone.
  ///
  /// The first detection time is kept across repeated polls; the details are
  /// refreshed, because the billing fields can arrive on a later poll than the
  /// verdict did (rollout, backend briefly unreachable).
  Future<void> recordFailure(ProfileFailure failure) async {
    final profileId = _profileId;
    if (profileId == null) return;
    final now = DateTime.now().toUtc();
    final AccountState next;
    switch (failure) {
      case ProfileSubscriptionExpiredFailure(:final details):
        final since = switch (state) {
          AccountExpired(:final detectedAt) => detectedAt,
          _ => now,
        };
        next = AccountExpired(details: details ?? AccountExpiry.none, detectedAt: since);
      case ProfileAccountUnavailableFailure(:final code):
        if (AccountEnvelope.isTransientCode(code)) return;
        final since = switch (state) {
          AccountUnavailable(code: final current, :final detectedAt) when current == code => detectedAt,
          _ => now,
        };
        next = AccountUnavailable(code: code, detectedAt: since);
      default:
        return;
    }
    if (next == state) return;
    loggy.info("account state -> $next");
    state = next;
    await _store.write(profileId: profileId, state: next);
  }

  /// A config was persisted for the active profile: whatever the verdict was,
  /// the account is serving again.
  Future<void> recordActive() async {
    if (state is! AccountActive) {
      loggy.info("account state -> active");
      state = const AccountActive();
    }
    await _store.clear();
  }
}
