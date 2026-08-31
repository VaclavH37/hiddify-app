import 'package:hiddify/features/auth/model/payment_provider.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/notifications/model/notification_dedup_state.dart';
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
  // MW `subscription-payment-provider` header (e.g. "google_play"). Null for
  // token-import users / non-Play plans → the standard expiry-reminder path.
  String? paymentProvider,
}) {
  final toCreate = <PendingNotification>[];
  var next = state;

  // There was a traffic-quota block here firing at 80 / 90 / 100% of the
  // monthly allowance, deduped per period. It was removed with the rest of the
  // usage UI: those notices told a subscriber exactly when they were about to
  // be moved to the slower hub, which is the one thing this design does not
  // want them to know. Consumption is still parsed and stored; nothing reads it.

  // ---- Subscription expiry / store renewal ----
  final daysRemaining = subInfo.expire.difference(now).inDays;
  // `> 365` also covers the parser's "infinite" expiry sentinel.
  final nonExpiring = daysRemaining > 365;
  if (!nonExpiring) {
    final anchorKey = subInfo.expire.toIso8601String();
    if (isStoreManagedProvider(paymentProvider)) {
      // Auto-renewing plans don't "expire" — suppress the countdown and instead
      // give one heads-up the day before the renewal date (on a store plan the
      // `expire` field IS the renewal date). Deduped once per anchor: when the
      // sub renews, `expire` advances, the anchor differs, and it's eligible
      // again next cycle.
      if (daysRemaining == 1 && next.renewalFiredAnchor != anchorKey) {
        toCreate.add((kind: NotificationKind.renewalReminder, thresholdValue: 1));
        next = next.copyWith(renewalFiredAnchor: anchorKey);
      }
    } else {
      // Non-auto-renewing: remind within 7 days of expiry, once per calendar day.
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
  }

  return (toCreate: toCreate, nextState: next);
}

/// Local calendar-day key (yyyy-MM-dd) used for the once-per-day expiry guard.
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
