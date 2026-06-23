import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/notifications/logic/notification_evaluator.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/notifications/model/notification_dedup_state.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
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

  group('quota thresholds', () {
    test('79.9% fires nothing', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 799),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(r.toCreate, isEmpty);
    });

    test('exactly 80% fires quota80 only', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 800),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(kinds(r), {NotificationKind.quota80});
      expect(r.toCreate.single.thresholdValue, 80);
      expect(r.nextState.quota80Fired, isTrue);
    });

    test('80→90 in the same period fires only quota90', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 900, refillDate: DateTime(2026, 7, 1)),
        state: NotificationDedupState(
          quotaPeriodKey: DateTime(2026, 7, 1).toIso8601String(),
          quota80Fired: true,
          lastConsumption: 800,
        ),
        now: now,
      );
      expect(kinds(r), {NotificationKind.quota90});
    });

    test('a jump from <80 to 95 fires both 80 and 90', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 950),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(kinds(r), {NotificationKind.quota80, NotificationKind.quota90});
    });

    test('100% fires all three on a fresh state', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 1000),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(kinds(r), {NotificationKind.quota80, NotificationKind.quota90, NotificationKind.quota100});
    });

    test('over 100% still fires quota100 once, then nothing', () {
      final first = evaluateNotifications(
        subInfo: sub(download: 1200),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(kinds(first), contains(NotificationKind.quota100));

      final second = evaluateNotifications(
        subInfo: sub(download: 1300),
        state: first.nextState,
        now: now,
      );
      expect(second.toCreate, isEmpty);
    });

    test('unlimited traffic never fires quota notifications', () {
      const total = ProfileParser.infiniteTrafficThreshold + 1;
      final r = evaluateNotifications(
        subInfo: sub(download: total, total: total),
        state: const NotificationDedupState(),
        now: now,
      );
      expect(r.toCreate, isEmpty);
    });
  });

  group('quota period reset', () {
    test('a changed refillDate re-arms the thresholds', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 850, refillDate: DateTime(2026, 8, 1)),
        state: NotificationDedupState(
          quotaPeriodKey: DateTime(2026, 7, 1).toIso8601String(),
          quota80Fired: true,
          quota90Fired: true,
          quota100Fired: true,
          lastConsumption: 1000,
        ),
        now: now,
      );
      expect(kinds(r), {NotificationKind.quota80});
    });

    test('a consumption drop (no refillDate) clears the fired flags', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 100),
        state: const NotificationDedupState(quota80Fired: true, lastConsumption: 850),
        now: now,
      );
      expect(r.toCreate, isEmpty);
      expect(r.nextState.quota80Fired, isFalse);
    });

    test('rising usage without a drop does not reset', () {
      final r = evaluateNotifications(
        subInfo: sub(download: 850),
        state: const NotificationDedupState(quota80Fired: true, lastConsumption: 800),
        now: now,
      );
      expect(r.toCreate, isEmpty);
      expect(r.nextState.quota80Fired, isTrue);
    });
  });

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
