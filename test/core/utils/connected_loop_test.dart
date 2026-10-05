import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/utils/connected_loop.dart';

/// The scheduler the rule-set updater and the Windows app updater share: it
/// runs only while the tunnel is up, because both fetch only through it.
void main() {
  group('ConnectedLoop', () {
    testWidgets('runs only while connected: after the first delay, then on the interval each run returns', (
      tester,
    ) async {
      var runs = 0;
      var stops = 0;
      final loop = ConnectedLoop(
        check: () async {
          runs++;
          return const Duration(hours: 24);
        },
        firstDelay: () => const Duration(seconds: 60),
        retryAfterFailure: const Duration(hours: 1),
        onStop: () => stops++,
      );

      await tester.pump(const Duration(hours: 2));
      expect(runs, 0, reason: 'never connected');

      loop.connected(true);
      await tester.pump(const Duration(seconds: 59));
      expect(runs, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(runs, 1);
      await tester.pump(const Duration(hours: 24));
      expect(runs, 2);

      loop.connected(false);
      expect(stops, 1);
      await tester.pump(const Duration(hours: 48));
      expect(runs, 2, reason: 'disconnected');

      loop.connected(true);
      await tester.pump(const Duration(seconds: 60));
      expect(runs, 3);
      loop.connected(false);
    });

    testWidgets('a repeated "connected" does not schedule a second run', (tester) async {
      var runs = 0;
      final loop = ConnectedLoop(
        check: () async {
          runs++;
          return const Duration(hours: 24);
        },
        firstDelay: () => const Duration(seconds: 60),
        retryAfterFailure: const Duration(hours: 1),
      );
      loop
        ..connected(true)
        ..connected(true);
      await tester.pump(const Duration(seconds: 60));
      expect(runs, 1);
      loop.connected(false);
    });

    testWidgets('a run that finishes after the disconnect schedules nothing', (tester) async {
      var runs = 0;
      final pending = Completer<Duration>();
      final loop = ConnectedLoop(
        check: () {
          runs++;
          return pending.future;
        },
        firstDelay: () => const Duration(seconds: 60),
        retryAfterFailure: const Duration(hours: 1),
      );
      loop.connected(true);
      await tester.pump(const Duration(seconds: 60));
      expect(runs, 1);

      loop.connected(false);
      pending.complete(const Duration(seconds: 1));
      await tester.pump(const Duration(hours: 1));
      expect(runs, 1);
    });

    testWidgets('a run that throws is retried after retryAfterFailure', (tester) async {
      var runs = 0;
      final loop = ConnectedLoop(
        check: () async {
          runs++;
          if (runs == 1) throw StateError('boom');
          return const Duration(hours: 24);
        },
        firstDelay: () => const Duration(seconds: 60),
        retryAfterFailure: const Duration(hours: 1),
      );
      loop.connected(true);
      await tester.pump(const Duration(seconds: 60));
      expect(runs, 1);
      await tester.pump(const Duration(minutes: 59));
      expect(runs, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(runs, 2);
      loop.connected(false);
    });
  });
}
