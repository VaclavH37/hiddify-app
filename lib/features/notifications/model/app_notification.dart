import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_notification.freezed.dart';

/// The kind of an in-app notification. Stored verbatim (`textEnum`) in the
/// `app_notifications` Drift table — the inbox/banner render localized copy
/// from `kind` + `thresholdValue` at display time, so the table never holds
/// rendered (locale-baked) strings.
enum NotificationKind {
  /// Traffic quota reached 80% of the monthly allowance.
  quota80,

  /// Traffic quota reached 90%.
  quota90,

  /// Traffic quota fully consumed (100%).
  quota100,

  /// Subscription is within a week of expiring (fires once per day).
  expiryReminder,

  /// Subscription token is fully expired with no renewal available — raised by
  /// the refresh loop when the API returns `4010` with no `new-url`.
  subscriptionExpired,
}

@freezed
class AppNotification with _$AppNotification {
  const factory AppNotification({
    required String id,
    required NotificationKind kind,
    // quota: 80 / 90 / 100; expiry: days remaining at fire time. Nullable for
    // forward-compatibility with kinds that carry no figure.
    int? thresholdValue,
    required DateTime createdAt,
    // "read" — flipped true when the inbox is opened; drives the bell badge.
    @Default(false) bool seen,
    // Swipe-away state for the connection-page banner; the row stays in the
    // inbox after dismissal.
    @Default(false) bool dismissed,
  }) = _AppNotification;
}
