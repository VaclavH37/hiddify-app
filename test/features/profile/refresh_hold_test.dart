import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';

/// A retryable 4012 holds the next unforced poll for `retry_after`, never
/// less than the scheduler's floor (the Worker's reply, §4.3).
void main() {
  const floor = ForegroundProfilesUpdateNotifier.interval;

  test('no retry_after, or one below the floor, holds for the floor', () {
    expect(refreshHoldFor(null), floor);
    expect(refreshHoldFor(const Duration(minutes: 5)), floor);
    expect(refreshHoldFor(floor), floor);
  });

  test('a longer retry_after is honoured as sent', () {
    expect(refreshHoldFor(const Duration(hours: 1)), const Duration(hours: 1));
    expect(refreshHoldFor(const Duration(days: 1)), const Duration(days: 1));
  });

  test('the hold applies only until its instant', () {
    final now = DateTime.utc(2026, 9, 15, 12);
    expect(refreshHeldBack(null, now), isFalse);
    expect(refreshHeldBack(now.add(const Duration(minutes: 1)), now), isTrue);
    expect(refreshHeldBack(now, now), isFalse);
    expect(refreshHeldBack(now.subtract(const Duration(minutes: 1)), now), isFalse);
  });
}
