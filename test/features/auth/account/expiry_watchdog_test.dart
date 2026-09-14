import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/account/notifier/expiry_watchdog.dart';

/// The watchdog's two decisions: is a refresh due now, and when to look next.
void main() {
  final expire = DateTime.utc(2026, 9, 14, 12);
  final before = expire.subtract(const Duration(days: 3));

  group('expiryRefreshDue', () {
    test('not before the expiry, nor inside the grace after it', () {
      expect(expiryRefreshDue(expire: expire, lastUpdate: before, now: expire, accountActive: true), isFalse);
      expect(
        expiryRefreshDue(
          expire: expire,
          lastUpdate: before,
          now: expire.add(expiryGrace).subtract(const Duration(seconds: 1)),
          accountActive: true,
        ),
        isFalse,
      );
    });

    test('due once the grace has passed and nothing was persisted since', () {
      expect(
        expiryRefreshDue(expire: expire, lastUpdate: before, now: expire.add(expiryGrace), accountActive: true),
        isTrue,
      );
    });

    test('a config persisted after the expiry answers the question', () {
      expect(
        expiryRefreshDue(
          expire: expire,
          lastUpdate: expire.add(const Duration(minutes: 1)),
          now: expire.add(const Duration(hours: 1)),
          accountActive: true,
        ),
        isFalse,
      );
    });

    test('a verdict on file means the Worker has already answered', () {
      expect(
        expiryRefreshDue(
          expire: expire,
          lastUpdate: before,
          now: expire.add(const Duration(hours: 1)),
          accountActive: false,
        ),
        isFalse,
      );
    });
  });

  group('expiryTimerDelay', () {
    test('fires at expiry plus the grace', () {
      expect(
        expiryTimerDelay(expire: expire, now: expire.subtract(const Duration(hours: 2))),
        const Duration(hours: 2) + expiryGrace,
      );
    });

    test('null when already due — the caller checks now', () {
      expect(expiryTimerDelay(expire: expire, now: expire.add(expiryGrace)), isNull);
      expect(expiryTimerDelay(expire: expire, now: expire.add(const Duration(days: 1))), isNull);
    });

    test('null beyond the horizon — a later emission or resume re-arms', () {
      expect(
        expiryTimerDelay(expire: expire, now: expire.subtract(expiryHorizon + const Duration(minutes: 1))),
        isNull,
      );
      expect(
        expiryTimerDelay(expire: expire, now: expire.subtract(expiryHorizon - const Duration(minutes: 1))),
        isNotNull,
      );
    });
  });

  test("the parser's infinite expiry never arms anything", () {
    final now = DateTime.utc(2026, 9, 14);
    expect(isNonExpiring(now.add(const Duration(days: 366)), now), isTrue);
    expect(isNonExpiring(now.add(const Duration(days: 30)), now), isFalse);
  });
}
