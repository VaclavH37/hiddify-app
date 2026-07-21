import 'package:drift/drift.dart' show Value;
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/notifications/data/notification_data_providers.dart';
import 'package:hiddify/features/notifications/logic/notification_evaluator.dart';
import 'package:hiddify/features/notifications/model/notification_dedup_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'notification_monitor.g.dart';

/// Watches the active profile's subscription and, on every emission, runs the
/// pure [evaluateNotifications] to create quota/expiry notifications and persist
/// the dedup state.
///
/// Lazy keepAlive provider — eagerly started from `App.build` via a bare
/// `ref.listen`, mirroring `ForegroundProfilesUpdateNotifier`.
@Riverpod(keepAlive: true)
class NotificationMonitor extends _$NotificationMonitor with AppLogger {
  // Serializes evaluations so overlapping emissions don't race the
  // read-modify-write of the dedup blob.
  Future<void> _chain = Future<void>.value();

  @override
  void build() {
    ref.listen(activeProfileProvider, (_, next) {
      final profile = next.valueOrNull;
      if (profile is! RemoteProfileEntity) return;
      final subInfo = profile.subInfo;
      if (subInfo == null) return;
      // MW subscription header — "google_play" routes to the renewal reminder
      // instead of the expiry countdown (mirrors account_section.dart's _header).
      final paymentProvider = profile.populatedHeaders?['subscription-payment-provider']?.toString().trim();
      _enqueue(profile.id, subInfo, paymentProvider);
    });
  }

  void _enqueue(String profileId, SubscriptionInfo subInfo, String? paymentProvider) {
    _chain = _chain.then((_) => _process(profileId, subInfo, paymentProvider)).catchError((Object e, StackTrace s) {
      loggy.warning("notification evaluation failed", e, s);
    });
  }

  Future<void> _process(String profileId, SubscriptionInfo subInfo, String? paymentProvider) async {
    final store = ref.read(notificationDedupStoreProvider);
    var state = store.read();
    // New active profile → discard stale markers so a re-import can't suppress
    // legitimate alerts.
    if (state.profileId != profileId) {
      state = NotificationDedupState(profileId: profileId);
    }

    final result = evaluateNotifications(
      subInfo: subInfo,
      state: state,
      now: DateTime.now(),
      paymentProvider: paymentProvider,
    );

    if (result.toCreate.isNotEmpty) {
      final dao = ref.read(notificationDataSourceProvider);
      for (final pending in result.toCreate) {
        await dao.insert(
          AppNotificationsCompanion.insert(
            id: const Uuid().v4(),
            kind: pending.kind,
            createdAt: DateTime.now(),
            thresholdValue: Value(pending.thresholdValue),
          ),
        );
      }
    }

    await store.write(result.nextState);
  }
}
