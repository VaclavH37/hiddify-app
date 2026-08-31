import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';

/// Localized presentation for a notification, derived from its [kind] +
/// [thresholdValue] at display time (the table stores no rendered strings).
typedef NotificationCopy = ({String title, String body, IconData icon});

NotificationCopy notificationCopy(AppNotification n, Translations t) {
  switch (n.kind) {
    case NotificationKind.expiryReminder:
      return (
        title: t.notifications.expiry.title,
        body: t.notifications.expiry.body(days: n.thresholdValue ?? 0),
        icon: FluentIcons.calendar_clock_24_regular,
      );
    case NotificationKind.renewalReminder:
      return (
        title: t.notifications.renewal.title,
        body: t.notifications.renewal.body,
        icon: FluentIcons.arrow_sync_24_regular,
      );
    case NotificationKind.subscriptionExpired:
      return (
        title: t.notifications.expired.title,
        body: t.notifications.expired.body,
        icon: FluentIcons.warning_24_regular,
      );
  }
}
