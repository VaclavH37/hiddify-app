import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'logout_notifier.g.dart';

/// Disconnects (if connected) then deletes the active profile, returning the
/// app to the unauthenticated state. The router redirect listener picks up
/// `hasAnyProfileProvider == false` and bounces to `/auth`.
@riverpod
class LogoutNotifier extends _$LogoutNotifier with AppLogger {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> logout() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final profile = await ref.read(activeProfileProvider.future);
      if (profile == null) {
        loggy.warning("logout called with no active profile");
        return;
      }

      // 1. Tear down the connection first. The connection notifier listens
      //    on activeProfileProvider; deleting the row before disconnecting
      //    can cause it to fire reconnect on a vanished profile.
      try {
        await ref.read(connectionNotifierProvider.notifier).abortConnection();
        // Brief settle delay so the disconnect transition completes before
        // the profile row is removed. Defensive — abortConnection awaits the
        // core call but the status stream takes a tick to update.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      } catch (e, st) {
        loggy.warning("disconnect during logout failed; proceeding with delete", e, st);
      }

      // 2. Delete row + JSON config file.
      final repo = ref.read(profileRepositoryProvider).requireValue;
      await repo
          .deleteById(profile.id, profile.active)
          .match((err) {
            loggy.error("failed to delete profile during logout", err);
            throw err;
          }, (_) => unit)
          .run();

      loggy.info("logout complete");
    });
  }
}
