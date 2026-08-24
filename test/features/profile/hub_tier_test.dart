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

  group('hubTierUntil', () {
    test('parses unix seconds', () {
      expect(hubTierUntil('1790000000'), DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000));
    });

    test('treats absent, zero, negative and unparseable as unknown', () {
      expect(hubTierUntil(null), isNull);
      expect(hubTierUntil(''), isNull);
      expect(hubTierUntil('0'), isNull);
      expect(hubTierUntil('-1'), isNull);
      expect(hubTierUntil('soon'), isNull);
      expect(hubTierUntil('17900.5'), isNull);
    });
  });

  group('hubTierCountdown', () {
    final now = DateTime(2026, 8, 23, 12);

    test('is null when the middleware sent no estimate', () {
      expect(hubTierCountdown(null, now), isNull);
    });

    // A header that went stale between refreshes. "Full speed in 0h" to someone
    // still on standby is worse than saying nothing.
    test('is null once the estimate has passed', () {
      expect(hubTierCountdown(now, now), isNull);
      expect(hubTierCountdown(now.subtract(const Duration(hours: 3)), now), isNull);
    });

    test('rounds hours up so it never under-promises', () {
      expect(hubTierCountdown(now.add(const Duration(hours: 4)), now), (value: 4, isDays: false));
      expect(hubTierCountdown(now.add(const Duration(hours: 4, minutes: 1)), now), (value: 5, isDays: false));
    });

    test('floors at one hour rather than showing zero', () {
      expect(hubTierCountdown(now.add(const Duration(minutes: 1)), now), (value: 1, isDays: false));
      expect(hubTierCountdown(now.add(const Duration(seconds: 30)), now), (value: 1, isDays: false));
    });

    test('switches to days at 48 hours', () {
      expect(hubTierCountdown(now.add(const Duration(hours: 47)), now), (value: 47, isDays: false));
      expect(hubTierCountdown(now.add(const Duration(hours: 48)), now), (value: 2, isDays: true));
      expect(hubTierCountdown(now.add(const Duration(hours: 49)), now), (value: 3, isDays: true));
    });
  });

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

    test('holds a change inside the dwell floor', () {
      expect(shouldReconnectForTier(HubTier.primary, HubTier.standby, now.subtract(hubTierDwell ~/ 2), now), isFalse);
    });

    test('applies a change once the dwell floor has elapsed', () {
      expect(shouldReconnectForTier(HubTier.primary, HubTier.standby, now.subtract(hubTierDwell), now), isTrue);
      expect(shouldReconnectForTier(HubTier.standby, HubTier.primary, now.subtract(hubTierDwell * 2), now), isTrue);
    });

    // The deferred-then-flipped-back case. `applied` is the tier the CORE holds,
    // not the last one observed, so a change the dwell floor suppressed cannot
    // come back as a reconnect to the tier already in use.
    test('does not reconnect to the tier the core is already running', () {
      const applied = HubTier.primary;
      expect(shouldReconnectForTier(applied, HubTier.standby, now, now), isFalse, reason: 'deferred');
      expect(
        shouldReconnectForTier(applied, HubTier.primary, now, now.add(const Duration(days: 1))),
        isFalse,
        reason: 'flipped back — the core never left primary, so there is nothing to apply',
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
