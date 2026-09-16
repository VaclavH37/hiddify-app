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

  test('the first re-check is early: retry_after or 30 s, whichever is later', () {
    expect(transientRecheckDelay(null), transientRecheckFloor);
    expect(transientRecheckDelay(const Duration(seconds: 5)), transientRecheckFloor);
    expect(transientRecheckDelay(const Duration(seconds: 31)), const Duration(seconds: 31));
    expect(transientRecheckDelay(const Duration(minutes: 15)), const Duration(minutes: 15));
  });

  test('the ladder asks about the account at most once a minute', () {
    final now = DateTime.utc(2026, 9, 17, 12);
    expect(verdictProbeDue(null, now), isTrue);
    expect(verdictProbeDue(now.subtract(const Duration(seconds: 59)), now), isFalse);
    expect(verdictProbeDue(now.subtract(const Duration(seconds: 60)), now), isTrue);
    expect(verdictProbeDue(now.subtract(const Duration(minutes: 5)), now), isTrue);
  });

  test('the hold applies only until its instant', () {
    final now = DateTime.utc(2026, 9, 15, 12);
    expect(refreshHeldBack(null, now), isFalse);
    expect(refreshHeldBack(now.add(const Duration(minutes: 1)), now), isTrue);
    expect(refreshHeldBack(now, now), isFalse);
    expect(refreshHeldBack(now.subtract(const Duration(minutes: 1)), now), isFalse);
  });
}
