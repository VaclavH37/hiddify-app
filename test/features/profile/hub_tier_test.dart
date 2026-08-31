import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/hub_tier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';

void main() {
  ProfileEntity profileWith(Map<String, dynamic>? headers) => ProfileEntity.remote(
    id: 'p1',
    active: true,
    name: 'Rayn',
    url: 'https://example.com/sub',
    lastUpdate: DateTime(2026, 8, 23),
    populatedHeaders: headers,
  );

  group('hubTierOf', () {
    test('reads the standby tier', () {
      expect(hubTierOf('standby'), HubTier.standby);
    });

    test('tolerates whitespace and casing', () {
      expect(hubTierOf('  STANDBY '), HubTier.standby);
      expect(hubTierOf('Standby'), HubTier.standby);
    });

    // The safe default is the one that costs us bandwidth, not the one that
    // costs a paying user their speed — so every ambiguous input is primary.
    test('defaults to primary for absent, blank, unknown and garbage values', () {
      expect(hubTierOf(null), HubTier.primary);
      expect(hubTierOf(''), HubTier.primary);
      expect(hubTierOf('   '), HubTier.primary);
      expect(hubTierOf('primary'), HubTier.primary);
      expect(hubTierOf('reserve'), HubTier.primary, reason: 'a future middleware value must not degrade the user');
      expect(hubTierOf('{"tier":"standby"}'), HubTier.primary);
    });
  });

  // `hubTierUntil` and `hubTierCountdown` had groups here. Both were deleted
  // with the quota card that displayed them — the countdown told a subscriber
  // when full speed returned, which is a statement that it had been withdrawn.

  group('shouldReconnectForTier', () {
    final now = DateTime(2026, 8, 23, 12);

    test('does nothing when the tier has not moved', () {
      expect(shouldReconnectForTier(HubTier.primary, HubTier.primary, null, now), isFalse);
      expect(
        shouldReconnectForTier(HubTier.standby, HubTier.standby, now.subtract(const Duration(days: 1)), now),
        isFalse,
      );
    });

    test('switches immediately when nothing has been switched yet', () {
      expect(shouldReconnectForTier(HubTier.primary, HubTier.standby, null, now), isTrue);
    });

    // The asymmetry is the point. Holding someone on the unmetered standby hub
    // costs nothing; holding them on the metered CN2-GIA hub spends the budget
    // the feature exists to protect. The middleware splits the directions the
    // same way, and a symmetric floor here would undo that for the heaviest
    // subscribers — whose primary leg (~4.4 h at 2.6× accrual) is SHORTER than
    // this floor, so it would bind on every single cycle.
    test('never delays the move TO standby, whatever the dwell says', () {
      for (final since in [now, now.subtract(hubTierDwell ~/ 2), now.subtract(const Duration(seconds: 1))]) {
        expect(
          shouldReconnectForTier(HubTier.primary, HubTier.standby, since, now),
          isTrue,
          reason: 'last switch $since — a delayed move to standby is metered traffic we pay for',
        );
      }
    });

    test('holds the RETURN to primary inside the dwell floor', () {
      expect(shouldReconnectForTier(HubTier.standby, HubTier.primary, now.subtract(hubTierDwell ~/ 2), now), isFalse);
    });

    test('applies the return once the dwell floor has elapsed', () {
      expect(shouldReconnectForTier(HubTier.standby, HubTier.primary, now.subtract(hubTierDwell), now), isTrue);
      expect(shouldReconnectForTier(HubTier.standby, HubTier.primary, now.subtract(hubTierDwell * 2), now), isTrue);
    });

    // The deferred-then-flipped-back case. `applied` is the tier the CORE holds,
    // not the last one observed, so a return the dwell floor suppressed cannot
    // come back as a reconnect to the tier already in use.
    test('does not reconnect to the tier the core is already running', () {
      const applied = HubTier.standby;
      expect(shouldReconnectForTier(applied, HubTier.primary, now, now), isFalse, reason: 'deferred');
      expect(
        shouldReconnectForTier(applied, HubTier.standby, now, now.add(const Duration(days: 1))),
        isFalse,
        reason: 'flipped back — the core never left standby, so there is nothing to apply',
      );
    });
  });

  group('subscriptionHeader', () {
    test('reads a persisted header', () {
      expect(subscriptionHeader(profileWith({'subscription-hub-tier': 'standby'}), 'subscription-hub-tier'), 'standby');
    });

    test('trims surrounding whitespace', () {
      expect(
        subscriptionHeader(profileWith({'subscription-hub-tier': ' standby '}), 'subscription-hub-tier'),
        'standby',
      );
    });

    test('is null for a missing profile, a missing map, a missing key and a blank value', () {
      expect(subscriptionHeader(null, 'subscription-hub-tier'), isNull);
      expect(subscriptionHeader(profileWith(null), 'subscription-hub-tier'), isNull);
      expect(subscriptionHeader(profileWith({}), 'subscription-hub-tier'), isNull);
      expect(subscriptionHeader(profileWith({'subscription-hub-tier': '  '}), 'subscription-hub-tier'), isNull);
    });

    test('stringifies non-string header values', () {
      expect(
        subscriptionHeader(profileWith({'subscription-hub-tier-until': 1790000000}), 'subscription-hub-tier-until'),
        '1790000000',
      );
    });
  });
}
