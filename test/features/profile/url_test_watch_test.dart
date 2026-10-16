import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';

/// The fast failover's window: every location timed out, stayed timed out for
/// [hubUrlTestWindow], and a re-test measured after that timed out as well.
void main() {
  final t0 = DateTime(2026, 10, 16, 12);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

  const timeout = 65535;
  List<ExitObservation> allTimedOut({DateTime? testedAt}) => [
    (delay: timeout, testedAt: testedAt),
    (delay: timeout, testedAt: testedAt),
  ];
  List<ExitObservation> oneHealthy({DateTime? testedAt}) => [
    (delay: timeout, testedAt: testedAt),
    (delay: 180, testedAt: testedAt),
  ];

  /// A watch that has opened its window at t0 and asked for a re-test at +10 s.
  UrlTestWatch awaitingRetest() {
    final watch = UrlTestWatch();
    expect(watch.observe(allTimedOut(testedAt: at(-1)), at(0)), UrlTestWatchStep.armWindow);
    expect(watch.windowElapsed(at(10)), UrlTestWatchStep.retest);
    return watch;
  }

  group('opening the window', () {
    test('the first all-timed-out result opens it', () {
      expect(UrlTestWatch().observe(allTimedOut(), at(0)), UrlTestWatchStep.armWindow);
    });

    test('repeats while it is open change nothing', () {
      final watch = UrlTestWatch()..observe(allTimedOut(), at(0));
      expect(watch.observe(allTimedOut(), at(3)), UrlTestWatchStep.none);
    });

    test('one location answering is not a verdict', () {
      expect(UrlTestWatch().observe(oneHealthy(), at(0)), UrlTestWatchStep.none);
    });

    test('nothing to judge (disconnected, or not tested yet) is not a verdict', () {
      expect(UrlTestWatch().observe(const [], at(0)), UrlTestWatchStep.none);
      expect(UrlTestWatch().observe(const [(delay: 0, testedAt: null)], at(0)), UrlTestWatchStep.none);
    });

    test('a clock that moved backwards opens it again', () {
      final watch = UrlTestWatch()..observe(allTimedOut(), at(0));
      expect(watch.observe(allTimedOut(), at(-60)), UrlTestWatchStep.armWindow);
    });
  });

  group('closing it', () {
    test('a location answering closes an open window', () {
      final watch = UrlTestWatch()..observe(allTimedOut(), at(0));
      expect(watch.observe(oneHealthy(), at(4)), UrlTestWatchStep.reset);
      expect(watch.windowElapsed(at(10)), UrlTestWatchStep.none);
    });

    test('a disconnect (an empty list) closes it', () {
      final watch = UrlTestWatch()..observe(allTimedOut(), at(0));
      expect(watch.observe(const [], at(4)), UrlTestWatchStep.reset);
    });

    test('a healthy result while waiting for the re-test closes it', () {
      final watch = awaitingRetest();
      expect(watch.observe(oneHealthy(testedAt: at(12)), at(13)), UrlTestWatchStep.reset);
      expect(watch.retestExpired(at(22)), UrlTestWatchStep.none);
    });

    test('reset forgets everything', () {
      final watch = awaitingRetest()..reset();
      expect(watch.observe(allTimedOut(testedAt: at(12)), at(13)), UrlTestWatchStep.armWindow);
    });
  });

  group('the window passing', () {
    test('asks for a re-test, not a verdict', () {
      final watch = UrlTestWatch()..observe(allTimedOut(), at(0));
      expect(watch.windowElapsed(at(10)), UrlTestWatchStep.retest);
    });

    test('a timer that fires early by the wall clock opens the window again', () {
      final watch = UrlTestWatch()..observe(allTimedOut(), at(0));
      expect(watch.windowElapsed(at(9)), UrlTestWatchStep.armWindow);
      expect(watch.windowElapsed(at(19)), UrlTestWatchStep.retest);
    });

    test('with no window open does nothing', () {
      expect(UrlTestWatch().windowElapsed(at(10)), UrlTestWatchStep.none);
    });
  });

  group('the verdict', () {
    test('a timeout measured after the re-test request confirms', () {
      final watch = awaitingRetest();
      expect(watch.observe(allTimedOut(testedAt: at(15)), at(16)), UrlTestWatchStep.confirm);
    });

    test('a timeout measured before the request does not: a stale list is not a re-test', () {
      final watch = awaitingRetest();
      expect(watch.observe(allTimedOut(testedAt: at(-1)), at(11)), UrlTestWatchStep.none);
      expect(watch.observe(allTimedOut(), at(12)), UrlTestWatchStep.none);
    });

    test('a confirmation closes the window', () {
      final watch = awaitingRetest()..observe(allTimedOut(testedAt: at(15)), at(16));
      expect(watch.retestExpired(at(22)), UrlTestWatchStep.none);
      expect(watch.observe(allTimedOut(testedAt: at(15)), at(17)), UrlTestWatchStep.armWindow);
    });

    test('no fresh result before the guard is silence: another window, not a verdict', () {
      final watch = awaitingRetest();
      expect(watch.retestExpired(at(22)), UrlTestWatchStep.armWindow);
      expect(watch.windowElapsed(at(32)), UrlTestWatchStep.retest);
    });

    test('the guard firing with no re-test pending does nothing', () {
      final watch = UrlTestWatch()..observe(allTimedOut(), at(0));
      expect(watch.retestExpired(at(12)), UrlTestWatchStep.none);
    });
  });
}
