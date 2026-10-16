import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/local_routing/model/egress_routing.dart';
import 'package:hiddify/features/connection/local_routing/model/local_routing_tracker.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';

/// The rules behind the "IP routing is on" warning.
void main() {
  const forwarding = EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: true);
  const clean = EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: false);

  /// A tracker over a probe whose answer the test sets, counting the calls.
  ({LocalRoutingTracker tracker, void Function(EgressRouting?) answer, int Function() probes}) setUpTracker([
    EgressRouting? initial = forwarding,
  ]) {
    EgressRouting? answer = initial;
    var probes = 0;
    final tracker = LocalRoutingTracker(() {
      probes++;
      return answer;
    });
    return (tracker: tracker, answer: (value) => answer = value, probes: () => probes);
  }

  LocalRoutingSignals connected(int delay) => (connected: true, accountBlocked: false, delay: delay);

  group('raising', () {
    test('a timed-out location plus forwarding on raises the issue', () {
      final t = setUpTracker();
      expect(t.tracker.update(connected(hubUrlTestTimeout)), LocalRoutingEffect.raised);
      expect(t.tracker.issue, const LocalRoutingIssue(routing: forwarding));
    });

    test('a timed-out location with forwarding off says nothing', () {
      final t = setUpTracker(clean);
      expect(t.tracker.update(connected(65535)), LocalRoutingEffect.none);
      expect(t.tracker.issue, isNull);
    });

    test('no answer from the core says nothing', () {
      final t = setUpTracker(null);
      expect(t.tracker.update(connected(65535)), LocalRoutingEffect.none);
      expect(t.tracker.issue, isNull);
    });

    test('forwarding on while traffic flows never raises it, and never probes', () {
      final t = setUpTracker();
      expect(t.tracker.update(connected(180)), LocalRoutingEffect.none);
      expect(t.tracker.issue, isNull);
      expect(t.probes(), 0);
    });

    test('an unmeasured location waits', () {
      final t = setUpTracker();
      expect(t.tracker.update(connected(0)), LocalRoutingEffect.none);
      expect(t.probes(), 0);
    });

    test('nothing is raised while disconnected or under an account verdict', () {
      final t = setUpTracker();
      expect(t.tracker.update((connected: false, accountBlocked: false, delay: 65535)), LocalRoutingEffect.none);
      expect(t.tracker.update((connected: true, accountBlocked: true, delay: 65535)), LocalRoutingEffect.none);
      expect(t.tracker.issue, isNull);
      expect(t.probes(), 0);
    });

    test('a second timeout keeps the issue without raising it again', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      expect(t.tracker.update(connected(65535)), LocalRoutingEffect.none);
      expect(t.tracker.issue, isNotNull);
    });
  });

  group('clearing', () {
    test('a probe that finds the setting off solves it', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      t.answer(clean);
      expect(t.tracker.recheck(), LocalRoutingEffect.solved);
      expect(t.tracker.issue, isNull);
    });

    test('a probe the core cannot answer also ends it', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      t.answer(null);
      expect(t.tracker.recheck(), LocalRoutingEffect.solved);
    });

    test('a live latency clears it', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      expect(t.tracker.update(connected(210)), LocalRoutingEffect.cleared);
      expect(t.tracker.issue, isNull);
    });

    test('a disconnect clears it', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      expect(t.tracker.update((connected: false, accountBlocked: false, delay: 65535)), LocalRoutingEffect.cleared);
    });

    test('an account verdict clears it: the verdict explains the timeouts', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      expect(t.tracker.update((connected: true, accountBlocked: true, delay: 65535)), LocalRoutingEffect.cleared);
    });

    test('a re-check with no issue up does nothing', () {
      final t = setUpTracker();
      expect(t.tracker.recheck(), LocalRoutingEffect.none);
      expect(t.probes(), 0);
    });
  });

  group('dismissal', () {
    test('lasts while the issue does', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      t.tracker.dismiss();
      t.tracker.recheck();
      t.tracker.update(connected(65535));
      expect(t.tracker.issue?.dismissed, isTrue);
    });

    test('a later issue shows again', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      t.tracker.dismiss();
      t.tracker.update((connected: false, accountBlocked: false, delay: 0));
      t.tracker.update(connected(65535));
      expect(t.tracker.issue, const LocalRoutingIssue(routing: forwarding));
    });

    test('with no issue up does nothing', () {
      final t = setUpTracker()..tracker.dismiss();
      expect(t.tracker.issue, isNull);
    });
  });

  group('explain, for the hub-reachability ladder', () {
    test('forwarding on explains the failure and raises the issue', () {
      final t = setUpTracker();
      expect(t.tracker.explain(), (explains: true, effect: LocalRoutingEffect.raised));
      expect(t.tracker.issue, isNotNull);
    });

    test('forwarding off does not, and clears a stale issue', () {
      final t = setUpTracker()..tracker.update(connected(65535));
      t.answer(clean);
      expect(t.tracker.explain(), (explains: false, effect: LocalRoutingEffect.solved));
      expect(t.tracker.issue, isNull);
    });

    test('no answer from the core does not explain anything', () {
      final t = setUpTracker(null);
      expect(t.tracker.explain(), (explains: false, effect: LocalRoutingEffect.none));
    });
  });
}
