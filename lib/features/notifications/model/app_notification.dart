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

  /// The account has lapsed with no renewal available — raised by the refresh
  /// loop on the middleware's expired verdict (a `4010` with no `new-url`, or
  /// a `4011`). The banner's action and the inbox row open the renewal screen.
  subscriptionExpired,

  /// The account is suspended, closed, deleted, pending or unknown — the
  /// middleware's `4012`. Not renewable; the renewal screen shows the reason
  /// and support instead. One row at a time with [subscriptionExpired]: the
  /// refresh loop swaps them when the verdict changes kind.
  accountUnavailable,
}

extension NotificationKindX on NotificationKind {
  /// Whether this notification is an account verdict, whose banner action and
  /// inbox row open the renewal screen.
  bool get opensRenewal => this == NotificationKind.subscriptionExpired || this == NotificationKind.accountUnavailable;
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
