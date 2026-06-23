import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/notifications/model/notification_dedup_state.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

/// A notification the evaluator wants created; the data layer supplies the
/// `id` and `createdAt`.
typedef PendingNotification = ({NotificationKind kind, int thresholdValue});

typedef EvaluationResult = ({List<PendingNotification> toCreate, NotificationDedupState nextState});

/// Pure, deterministic core of the notification system. Given the current
/// [subInfo], the persisted dedup [state], and the wall-clock [now], it returns
/// the notifications to create and the next dedup state to persist.
///
/// Intentionally free of Drift / Riverpod / ambient `DateTime.now()` so it is
/// fully unit-testable: it recomputes ratio and days-remaining from [now]
/// rather than using `SubscriptionInfo`'s clock-based getters.
EvaluationResult evaluateNotifications({
  required SubscriptionInfo subInfo,
  required NotificationDedupState state,
  required DateTime now,
}) {
  final toCreate = <PendingNotification>[];
  var next = state;

  // ---- Traffic quota: 80% / 90% / 100%, once per period ----
  final unlimitedTraffic = subInfo.total > ProfileParser.infiniteTrafficThreshold;
  if (!unlimitedTraffic && subInfo.total > 0) {
    final periodKey = subInfo.refillDate?.toIso8601String();
    final consumption = subInfo.consumption;

    // New quota period → clear the fired flags. Detected either by a changed
    // `refillDate`, or (when the header is absent) by a consumption drop, since
    // usage only ever grows within a single period.
    final periodChangedByRefill = periodKey != null && periodKey != next.quotaPeriodKey;
    final periodChangedByDrop = periodKey == null && consumption < next.lastConsumption;
    if (periodChangedByRefill || periodChangedByDrop) {
      next = next.copyWith(
        quotaPeriodKey: periodKey,
        quota80Fired: false,
        quota90Fired: false,
        quota100Fired: false,
      );
    }

    final ratio = consumption / subInfo.total;
    // Fire each newly-crossed threshold (a jump past several at once fires all
    // of them, each exactly once).
    if (ratio >= 0.80 && !next.quota80Fired) {
      toCreate.add((kind: NotificationKind.quota80, thresholdValue: 80));
      next = next.copyWith(quota80Fired: true);
    }
    if (ratio >= 0.90 && !next.quota90Fired) {
      toCreate.add((kind: NotificationKind.quota90, thresholdValue: 90));
      next = next.copyWith(quota90Fired: true);
    }
    if (ratio >= 1.0 && !next.quota100Fired) {
      toCreate.add((kind: NotificationKind.quota100, thresholdValue: 100));
      next = next.copyWith(quota100Fired: true);
    }

    next = next.copyWith(lastConsumption: consumption);
  }

  // ---- Subscription expiry: within 7 days, once per calendar day ----
  final daysRemaining = subInfo.expire.difference(now).inDays;
  // `> 365` also covers the parser's "infinite" expiry sentinel.
  final nonExpiring = daysRemaining > 365;
  if (!nonExpiring) {
    final anchorKey = subInfo.expire.toIso8601String();
    // Subscription extended / changed → reset the per-day marker so the next
    // approach to expiry reminds again.
    if (next.expiryAnchorKey != anchorKey) {
      next = next.copyWith(expiryAnchorKey: anchorKey, expiryLastFiredDay: null);
    }
    if (daysRemaining >= 0 && daysRemaining <= 7) {
      final today = _dayKey(now);
      if (next.expiryLastFiredDay != today) {
        toCreate.add((kind: NotificationKind.expiryReminder, thresholdValue: daysRemaining));
        next = next.copyWith(expiryLastFiredDay: today);
      }
    }
  }

  return (toCreate: toCreate, nextState: next);
}

/// Local calendar-day key (yyyy-MM-dd) used for the once-per-day expiry guard.
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
