import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/notifications/logic/notification_evaluator.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/notifications/model/notification_dedup_state.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

void main() {
  // Fixed clock so the evaluator is deterministic.
  final now = DateTime(2026, 6, 23, 12);

  // A subscription with no quota pressure and an expiry well outside the
  // 7-day window (100 days), so only the field under test moves things.
  SubscriptionInfo sub({
    int upload = 0,
    int download = 0,
    int total = 1000,
    DateTime? expire,
    DateTime? refillDate,
  }) {
    return SubscriptionInfo(
      upload: upload,
      download: download,
      total: total,
      expire: expire ?? now.add(const Duration(days: 100)),
      refillDate: refillDate,
    );
  }

  Set<NotificationKind> kinds(EvaluationResult r) => r.toCreate.map((e) => e.kind).toSet();

  // The `quota thresholds` and `quota period reset` groups lived here. They
  // went with the notifications themselves: a "you have used 90% of your data"
  // notice is the clearest possible warning that throttling is imminent, which
  // is the one thing the subscriber is not meant to be able to work out.

  group('expiry reminder', () {
    test('8 days out fires nothing', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 8))),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(r.toCreate, isEmpty);
    });

    test('7 days out fires an expiry reminder', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 7))),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(kinds(r), {NotificationKind.expiryReminder});
      expect(r.toCreate.single.thresholdValue, 7);
    });

    test('a second evaluation the same day does not repeat', () {
      final expire = now.add(const Duration(days: 3));
      final r = evaluateNotifications(
        subInfo: sub(expire: expire),
        state: NotificationDedupState(
          expiryAnchorKey: expire.toIso8601String(),
          expiryLastFiredDay: '2026-06-23',
        ),
        now: now,
      );
      expect(r.toCreate, isEmpty);
    });

    test('the next calendar day fires again while still in the window', () {
      final expire = now.add(const Duration(days: 3));
      final r = evaluateNotifications(
        subInfo: sub(expire: expire),
        state: NotificationDedupState(
          expiryAnchorKey: expire.toIso8601String(),
          expiryLastFiredDay: '2026-06-22',
        ),
        now: now,
      );
      expect(kinds(r), {NotificationKind.expiryReminder});
    });

    test('extending beyond a week stops reminders and resets the marker', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 30))),
        state: NotificationDedupState(
          expiryAnchorKey: now.add(const Duration(days: 2)).toIso8601String(),
          expiryLastFiredDay: '2026-06-23',
        ),
        now: now,
      );
      expect(r.toCreate, isEmpty);
      expect(r.nextState.expiryLastFiredDay, isNull);
    });

    test('non-expiring subscriptions never fire', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 400))),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(r.toCreate, isEmpty);
    });

    test('an already-expired subscription does not fire', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.subtract(const Duration(days: 2))),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(r.toCreate, isEmpty);
    });

    test('a Google Play subscriber never gets the expiry reminder', () {
      // 5 days out — inside the 7-day window, but Play auto-renews.
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 5))),
        state: const NotificationDedupState(),
        now: now,
        paymentProvider: 'google_play',
      );
      expect(r.toCreate, isEmpty);
    });
  });

  group('store renewal reminder', () {
    test('fires the day before renewal (1 day out)', () {
      final expire = now.add(const Duration(days: 1));
      final r = evaluateNotifications(
        subInfo: sub(expire: expire),
        state: const NotificationDedupState(),
        now: now,
        paymentProvider: 'google_play',
      );
      expect(kinds(r), {NotificationKind.renewalReminder});
      expect(r.toCreate.single.thresholdValue, 1);
      expect(r.nextState.renewalFiredAnchor, expire.toIso8601String());
    });

    test('does not fire earlier than the day before (2 days out)', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 2))),
        state: const NotificationDedupState(),
        now: now,
        paymentProvider: 'google_play',
      );
      expect(r.toCreate, isEmpty);
    });

    test('does not repeat once fired for the same renewal anchor', () {
      final expire = now.add(const Duration(days: 1));
      final r = evaluateNotifications(
        subInfo: sub(expire: expire),
        state: NotificationDedupState(renewalFiredAnchor: expire.toIso8601String()),
        now: now,
        paymentProvider: 'google_play',
      );
      expect(r.toCreate, isEmpty);
    });

    test('fires again after the sub renews (anchor advanced)', () {
      final expire = now.add(const Duration(days: 1));
      final r = evaluateNotifications(
        subInfo: sub(expire: expire),
        // Marker still points at last cycle's (now-past) renewal date.
        state: NotificationDedupState(
          renewalFiredAnchor: now.subtract(const Duration(days: 29)).toIso8601String(),
        ),
        now: now,
        paymentProvider: 'google_play',
      );
      expect(kinds(r), {NotificationKind.renewalReminder});
    });

    test('a non-store provider at 1 day out still gets the expiry reminder', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 1))),
        state: const NotificationDedupState(),
        now: now,
        paymentProvider: 'nowpayments',
      );
      expect(kinds(r), {NotificationKind.expiryReminder});
    });

    test('app_store renews, so it gets the reminder and not the countdown', () {
      // The App Store manages renewal exactly as Play does, so `expire` is a
      // renewal date. Reading it as an expiry would tell a paying subscriber
      // their plan is about to lapse every single billing cycle.
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 1))),
        state: const NotificationDedupState(),
        now: now,
        paymentProvider: 'app_store',
      );
      expect(kinds(r), {NotificationKind.renewalReminder});
    });

    test('app_store suppresses the 7-day countdown', () {
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 5))),
        state: const NotificationDedupState(),
        now: now,
        paymentProvider: 'app_store',
      );
      expect(kinds(r), isEmpty);
    });

    test('an unknown provider degrades to the expiry countdown', () {
      // The middleware owns this vocabulary. A value this build has never seen
      // must not be treated as auto-renewing, or a lapsing plan goes unwarned.
      final r = evaluateNotifications(
        subInfo: sub(expire: now.add(const Duration(days: 5))),
        state: const NotificationDedupState(),
        now: now,
        paymentProvider: 'some_future_provider',
      );
      expect(kinds(r), {NotificationKind.expiryReminder});
    });
  });

  test('the evaluator is deterministic', () {
    final subInfo = sub(download: 950, expire: now.add(const Duration(days: 5)));
    const state = NotificationDedupState();
    final a = evaluateNotifications(subInfo: subInfo, state: state, now: now);
    final b = evaluateNotifications(subInfo: subInfo, state: state, now: now);
    expect(kinds(a), kinds(b));
    expect(a.nextState, b.nextState);
  });
}
