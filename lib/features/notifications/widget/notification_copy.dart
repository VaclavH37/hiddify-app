import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';

/// How urgent a notification is; the banner and the inbox tint its icon with
/// this, so an expired subscription no longer looks like a renewal reminder.
enum NotificationSeverity { info, warning, danger }

/// Localized presentation for a notification, derived from its [kind] +
/// [thresholdValue] at display time (the table stores no rendered strings).
typedef NotificationCopy = ({String title, String body, IconData icon, NotificationSeverity severity});

NotificationCopy notificationCopy(AppNotification n, Translations t) {
  switch (n.kind) {
    case NotificationKind.expiryReminder:
      return (
        title: t.notifications.expiry.title,
        body: t.notifications.expiry.body(days: n.thresholdValue ?? 0),
        icon: Icons.schedule_rounded,
        severity: NotificationSeverity.warning,
      );
    case NotificationKind.renewalReminder:
      return (
        title: t.notifications.renewal.title,
        body: t.notifications.renewal.body,
        icon: Icons.autorenew_rounded,
        severity: NotificationSeverity.info,
      );
    case NotificationKind.subscriptionExpired:
      return (
        title: t.notifications.expired.title,
        body: t.notifications.expired.body,
        icon: Icons.warning_amber_rounded,
        severity: NotificationSeverity.danger,
      );
  }
}

/// The icon colour for a notification's severity.
Color notificationTint(NotificationCopy copy, RaynPalette palette) => switch (copy.severity) {
  NotificationSeverity.info => palette.accentText,
  NotificationSeverity.warning => palette.warning,
  NotificationSeverity.danger => palette.danger,
};
