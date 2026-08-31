import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_notification.freezed.dart';

/// The kind of an in-app notification. Stored verbatim (`textEnum`) in the
/// `app_notifications` Drift table — the inbox/banner render localized copy
/// from `kind` + `thresholdValue` at display time, so the table never holds
/// rendered (locale-baked) strings.
/// The `quota80` / `quota90` / `quota100` kinds were removed: usage is no
/// longer surfaced anywhere, and a "you have used 90% of your data" notice is
/// the clearest possible signal that throttling is about to happen. Rows
/// carrying them are deleted by the v11 migration, because `textEnum` resolves
/// by NAME and would throw on one it no longer knows.
enum NotificationKind {
  /// Subscription is within a week of expiring (fires once per day). Only for
  /// non-auto-renewing plans; Google Play subscribers get [renewalReminder]
  /// instead.
  expiryReminder,

  /// Google Play (auto-renewing) subscription renews tomorrow — a single
  /// heads-up the day before the renewal date, in place of the expiry countdown.
  renewalReminder,

  /// Subscription token is fully expired with no renewal available — raised by
  /// the refresh loop when the API returns `4010` with no `new-url`.
  subscriptionExpired,
}

@freezed
class AppNotification with _$AppNotification {
  const factory AppNotification({
    required String id,
    required NotificationKind kind,
    // Expiry: days remaining at fire time. Nullable for kinds that carry no
    // figure, which is now most of them.
    int? thresholdValue,
    required DateTime createdAt,
    // "read" — flipped true when the inbox is opened; drives the bell badge.
    @Default(false) bool seen,
    // Swipe-away state for the connection-page banner; the row stays in the
    // inbox after dismissal.
    @Default(false) bool dismissed,
  }) = _AppNotification;
}
