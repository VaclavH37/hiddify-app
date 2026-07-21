import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';

RaynOffer _offer(
  String basePlanId, {
  String? offerId,
  bool isTrial = false,
  String token = '',
  String iso = 'P1M',
}) =>
    RaynOffer(
      basePlanId: basePlanId,
      offerId: offerId,
      offerToken: token.isEmpty ? '$basePlanId-${offerId ?? 'base'}' : token,
      formattedPrice: '\$0.00',
      priceAmountMicros: 0,
      priceCurrencyCode: 'USD',
      billingPeriodIso: iso,
      isTrial: isTrial,
    );

void main() {
  group('reduceUpgradeOffers', () {
    test('prefers the plain base plan over the trial offer', () {
      final result = reduceUpgradeOffers([
        _offer('monthly', offerId: 'trial', isTrial: true, token: 'monthly-trial'),
        _offer('monthly', token: 'monthly-base'),
      ]);
      expect(result, hasLength(1));
      expect(result.single.offerToken, 'monthly-base');
      expect(result.single.isTrial, isFalse);
    });

    test('falls back to the trial when it is the only offer for a plan', () {
      final result = reduceUpgradeOffers([
        _offer('monthly', offerId: 'trial', isTrial: true, token: 'monthly-trial'),
      ]);
      expect(result.single.offerToken, 'monthly-trial');
    });

    test('orders the base plans monthly → quarter → annual', () {
      final result = reduceUpgradeOffers([_offer('annual'), _offer('monthly'), _offer('quarter')]);
      expect(result.map((o) => o.basePlanId), ['monthly', 'quarter', 'annual']);
    });

    test('empty in → empty out', () {
      expect(reduceUpgradeOffers([]), isEmpty);
    });
  });

  group('projectedRenewal', () {
    // Renewal now follows the standard Play cycle from today — the current plan
    // ends immediately on switch, so no remaining-time is carried over.
    final from = DateTime(2026, 1, 10);

    test('adds one billing period (monthly)', () {
      expect(projectedRenewal(from, 'P1M'), DateTime(2026, 2, 10));
    });

    test('adds a quarter (P3M)', () {
      expect(projectedRenewal(from, 'P3M'), DateTime(2026, 4, 10));
    });

    test('adds a year (P1Y)', () {
      expect(projectedRenewal(from, 'P1Y'), DateTime(2027, 1, 10));
    });

    test('rolls the year over when months overflow', () {
      // Nov 10 + 3 months → Feb 10 next year.
      expect(projectedRenewal(DateTime(2026, 11, 10), 'P3M'), DateTime(2027, 2, 10));
    });

    test('normalizes an overflowing day-of-month', () {
      // Jan 31 + 1 month = Feb 31 → Mar 3 (2026 non-leap), matching DateTime normalization.
      expect(projectedRenewal(DateTime(2026, 1, 31), 'P1M'), DateTime(2026, 3, 3));
    });
  });

  group('periodMonths', () {
    test('parses ISO-8601 billing periods', () {
      expect(periodMonths('P1M'), 1);
      expect(periodMonths('P3M'), 3);
      expect(periodMonths('P1Y'), 12);
    });

    test('defaults to 1 for an unrecognized period', () {
      expect(periodMonths('P0D'), 1);
    });
  });
}
