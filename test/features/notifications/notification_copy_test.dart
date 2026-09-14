import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/notifications/widget/notification_copy.dart';
import 'package:hiddify/gen/translations.g.dart';

/// Every kind renders, and only the two account verdicts open the renewal
/// screen — with the right word on the banner's action.
void main() {
  final t = AppLocale.en.buildSync();
  AppNotification of(NotificationKind kind) =>
      AppNotification(id: 'n', kind: kind, thresholdValue: 3, createdAt: DateTime.utc(2026, 9, 14));

  test('every kind has a title and a body', () {
    for (final kind in NotificationKind.values) {
      final copy = notificationCopy(of(kind), t);
      expect(copy.title, isNotEmpty, reason: '$kind');
      expect(copy.body, isNotEmpty, reason: '$kind');
    }
  });

  test('the account verdicts are the danger ones and open the renewal screen', () {
    for (final kind in NotificationKind.values) {
      final copy = notificationCopy(of(kind), t);
      final verdict = kind == NotificationKind.subscriptionExpired || kind == NotificationKind.accountUnavailable;
      expect(kind.opensRenewal, verdict, reason: '$kind');
      expect(copy.severity == NotificationSeverity.danger, verdict, reason: '$kind');
    }
  });

  test('the banner action says renew for a lapsed plan, details for an unavailable account', () {
    expect(notificationActionLabel(of(NotificationKind.subscriptionExpired), t), t.notifications.expired.action);
    expect(notificationActionLabel(of(NotificationKind.accountUnavailable), t), t.notifications.unavailable.action);
  });
}
