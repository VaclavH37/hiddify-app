import 'package:dartx/dartx.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/notifications/data/notification_data_providers.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
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
    });

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
          final result = await ref.read(profileRepositoryProvider).requireValue.upsertRemote(profile.url).run();
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
              }
            },
            (_) async {
              loggy.debug("profile [${profile.id}] updated successfully");
              // A good config returned — clear any standing "expired" prompt.
              await _clearSubscriptionExpired();
              ref
                  .read(inAppNotificationControllerProvider)
                  .showSuccessToast(t.pages.profiles.msg.update.successNamed(name: profile.name));
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
