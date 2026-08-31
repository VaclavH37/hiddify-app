import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/config_slot.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/features/profile/model/hub_tier.dart';

String _config(List<String> servers) => jsonEncode({
  'outbounds': [
    for (final server in servers) {'type': 'vless', 'tag': 'exit-$server', 'server': server, 'server_port': 443},
  ],
});

void main() {
  final now = DateTime(2026, 8, 28, 12);

  group('allExitsTimedOut', () {
    const timedOut = 65535;

    test('every exit timed out is a verdict', () {
      expect(allExitsTimedOut([timedOut, timedOut, timedOut]), isTrue);
    });

    test('one healthy exit is not', () {
      expect(allExitsTimedOut([timedOut, 180, timedOut]), isFalse);
    });

    test('an UNTESTED exit is not a verdict either', () {
      // The core reports 0 for an exit it has not swept yet. Reading a
      // half-swept group as "all dead" would fail over on a partial result.
      expect(allExitsTimedOut([timedOut, 0, timedOut]), isFalse);
    });

    test('an empty group is never a verdict', () {
      expect(allExitsTimedOut(const <int>[]), isFalse);
    });

    test('accepts anything at or above the threshold, not just 65535', () {
      expect(allExitsTimedOut([hubUrlTestTimeout]), isTrue);
      expect(allExitsTimedOut([hubUrlTestTimeout - 1]), isFalse);
    });
  });

  group('urlTestFailureConfirmed', () {
    test('nothing seen yet is never confirmed', () {
      expect(urlTestFailureConfirmed(null, now), isFalse);
    });

    test('not confirmed inside the window', () {
      expect(urlTestFailureConfirmed(now.subtract(const Duration(seconds: 4)), now), isFalse);
    });

    test('confirmed at the window', () {
      expect(urlTestFailureConfirmed(now.subtract(hubUrlTestWindow), now), isTrue);
    });

    test('a stamp in the future is not a confirmation', () {
      // The clock moved backwards between stamping and checking. That is not a
      // measurement, and acting on it would fail over instantly; the caller
      // re-stamps instead.
      expect(urlTestFailureConfirmed(now.add(const Duration(minutes: 5)), now), isFalse);
    });
  });

  group('failoverAllowed', () {
    bool allowed({
      ConfigSlot slot = ConfigSlot.primary,
      HubTier servedTier = HubTier.primary,
      bool hasStandbyCache = true,
      int recentFlipCount = 0,
    }) => failoverAllowed(
      slot: slot,
      servedTier: servedTier,
      hasStandbyCache: hasStandbyCache,
      recentFlipCount: recentFlipCount,
    );

    test('allows a failover from the primary slot on the primary tier with a cache', () {
      expect(allowed(), isTrue);
    });

    test('refuses when there is no standby cache', () {
      // Better a dead primary the client can still refresh from than a restart
      // onto nothing.
      expect(allowed(hasStandbyCache: false), isFalse);
    });

    test('refuses when already on a forced standby leg', () {
      expect(allowed(slot: ConfigSlot.standby), isFalse);
    });

    test('refuses when the MIDDLEWARE is already serving the standby hub', () {
      // The quota axis, not ours. A subscriber over their allowance has the
      // standby hub in their primary slot, so the active config and the
      // precached one dial the same place — a failover would restart the core
      // onto an identical destination and spend a flap-cap entry for nothing.
      expect(allowed(servedTier: HubTier.standby), isFalse);
    });

    test('refuses at the flap cap, and allows just below it', () {
      expect(allowed(recentFlipCount: hubFlapCap - 1), isTrue);
      expect(allowed(recentFlipCount: hubFlapCap), isFalse);
    });
  });

  group('standbyLeaseExpired', () {
    test('a fresh leg has not expired', () {
      expect(standbyLeaseExpired(now.subtract(const Duration(hours: 1)), now), isFalse);
    });

    test('expires at the lease', () {
      expect(standbyLeaseExpired(now.subtract(hubStandbyLease), now), isTrue);
    });

    test('a missing start counts as expired, not as forever', () {
      // Otherwise a cleared preference strands the client on standby with
      // nothing left to time out.
      expect(standbyLeaseExpired(null, now), isTrue);
    });

    test('a start in the future counts as expired', () {
      expect(standbyLeaseExpired(now.add(const Duration(days: 365)), now), isTrue);
    });
  });

  group('retryPrimaryDue', () {
    test('not due inside the floor', () {
      expect(retryPrimaryDue(now.subtract(const Duration(minutes: 5)), now), isFalse);
    });

    test('due at the floor', () {
      expect(retryPrimaryDue(now.subtract(hubRetryPrimaryFloor), now), isTrue);
    });

    test('never due when there is no standby leg to retry', () {
      expect(retryPrimaryDue(null, now), isFalse);
    });
  });

  group('failoverAttemptDue', () {
    test('a client that has never reverted may attempt immediately', () {
      expect(failoverAttemptDue(null, now), isTrue);
    });

    test('backs off inside the window after a revert', () {
      // A revert means the device was offline. Repeating two core restarts
      // every cycle to re-learn that is a heavy price for no new information.
      expect(failoverAttemptDue(now.subtract(const Duration(minutes: 20)), now), isFalse);
    });

    test('attempts again once the backoff has passed', () {
      expect(failoverAttemptDue(now.subtract(hubOfflineBackoff), now), isTrue);
    });

    test('a revert stamped in the future does not suppress attempts forever', () {
      expect(failoverAttemptDue(now.add(const Duration(days: 365)), now), isTrue);
    });
  });

  group('recentFlips', () {
    test('keeps flips inside the window and drops older ones', () {
      final kept = now.subtract(const Duration(hours: 3));
      final dropped = now.subtract(hubFlapWindow + const Duration(minutes: 1));
      expect(recentFlips([kept.toIso8601String(), dropped.toIso8601String()], now), [kept]);
    });

    test('drops unparseable entries rather than counting them', () {
      // Counting corruption toward a cap that suppresses failover would
      // disable the feature silently.
      expect(recentFlips(['not-a-date', ''], now), isEmpty);
    });

    test('drops future entries', () {
      // A clock that jumps forward would otherwise suppress failover until it
      // caught up.
      expect(recentFlips([now.add(const Duration(days: 365)).toIso8601String()], now), isEmpty);
    });

    test('handles an absent list', () {
      expect(recentFlips(null, now), isEmpty);
    });
  });

  group('bumpCounter', () {
    test('increments from zero and from a running value', () {
      expect(bumpCounter(0), 1);
      expect(bumpCounter(7), 8);
    });

    test('saturates at the cap rather than overflowing', () {
      // A saturated window under-reports; it must never wrap or grow unbounded.
      expect(bumpCounter(hubCounterCap), hubCounterCap);
      expect(bumpCounter(hubCounterCap - 1), hubCounterCap);
    });

    test('treats a negative stored value as corruption and restarts from zero', () {
      expect(bumpCounter(-4), 1);
    });
  });

  group('settleCounter', () {
    test('subtracts what was delivered', () {
      expect(settleCounter(3, 3), 0);
    });

    test('PRESERVES checks that landed while the request was in flight', () {
      // The reason this subtracts instead of zeroing: two checks arrived after
      // the request was built, and they have not been reported yet.
      expect(settleCounter(5, 3), 2);
    });

    test('floors at zero rather than going negative', () {
      expect(settleCounter(2, 9), 0);
      expect(settleCounter(-1, 0), 0);
      expect(settleCounter(3, -1), 3);
    });
  });

  group('hubDigest', () {
    test('is stable across outbound order and duplication', () {
      // The middleware re-tags and re-groups exits continuously; only the
      // address set is meaningful.
      expect(hubDigest(_config(['1.2.3.4', '5.6.7.8'])), hubDigest(_config(['5.6.7.8', '1.2.3.4', '1.2.3.4'])));
    });

    test('changes when the hub address changes', () {
      expect(hubDigest(_config(['1.2.3.4'])), isNot(hubDigest(_config(['9.9.9.9']))));
    });

    test('never contains the address it fingerprints', () {
      // It is written to a preference file and quoted in logs.
      expect(hubDigest(_config(['203.0.113.77'])), isNot(contains('203.0.113')));
    });

    test('returns null for anything it cannot read as a config', () {
      for (final raw in ['', 'not json', '[]', '{}', '{"outbounds":[]}', '{"outbounds":"nope"}']) {
        expect(hubDigest(raw), isNull, reason: 'input: $raw');
      }
    });

    test('ignores outbounds with no server, such as the built-in groups', () {
      expect(
        hubDigest('{"outbounds":[{"type":"selector","tag":"select"},{"type":"vless","server":"1.2.3.4"}]}'),
        hubDigest(_config(['1.2.3.4'])),
      );
    });
  });

  group('primaryHubMoved', () {
    bool moved(String? stored, String? current, {HubTier from = HubTier.primary, HubTier to = HubTier.primary}) =>
        primaryHubMoved(storedDigest: stored, currentDigest: current, storedTier: from, currentTier: to);

    test('detects a changed fingerprint at a stable tier', () {
      expect(moved('aaaa', 'bbbb'), isTrue);
    });

    test('an unchanged fingerprint is not a move', () {
      expect(moved('aaaa', 'aaaa'), isFalse);
    });

    test('a missing fingerprint on either side is no opinion, never a move', () {
      // A parse failure is not evidence that the hub moved, and acting on one
      // would bounce the client back to a hub that is still blocked.
      expect(moved(null, 'bbbb'), isFalse);
      expect(moved('aaaa', null), isFalse);
      expect(moved(null, null), isFalse);
    });

    test('a QUOTA-TIER FLIP is never read as a hub rotation', () {
      // The case the middleware team caught. Crossing the rolling allowance
      // moves the ordinary response onto the standby hub, changing the same
      // address for a reason that has nothing to do with reachability. Reading
      // it as a rotation returns the client to a still-blocked primary, spends
      // one of hubFlapCap, and emits a false `recovered` — corrupting the only
      // signal the middleware has for a lifted block.
      expect(moved('aaaa', 'bbbb', to: HubTier.standby), isFalse);
      expect(moved('aaaa', 'bbbb', from: HubTier.standby), isFalse);
    });

    test('a rotation is still detected once the tier is stable again', () {
      // The guard defers the question rather than answering it wrongly; a later
      // observation at a matching tier resolves it.
      expect(moved('aaaa', 'bbbb', from: HubTier.standby, to: HubTier.standby), isTrue);
    });
  });
}
