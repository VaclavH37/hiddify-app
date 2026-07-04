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
    final from = DateTime(2026, 1, 10);

    test('adds remaining days plus the billing period (monthly)', () {
      // 20 days remaining + 1 month → 30 Jan + 1 month = 30 Feb → 2 Mar (normalized).
      expect(projectedRenewal(from, 20, 'P1M'), DateTime(2026, 2, 30));
    });

    test('adds a quarter (P3M)', () {
      expect(projectedRenewal(from, 5, 'P3M'), DateTime(2026, 4, 15));
    });

    test('adds a year (P1Y)', () {
      expect(projectedRenewal(from, 0, 'P1Y'), DateTime(2027, 1, 10));
    });

    test('rolls the year over when months overflow', () {
      // Oct 10 + 5 days + 3 months → Nov 15 + 3 → Feb 15 next year.
      expect(projectedRenewal(DateTime(2026, 11, 10), 5, 'P3M'), DateTime(2027, 2, 15));
    });

    test('clamps negative remaining days to zero', () {
      expect(projectedRenewal(from, -30, 'P1M'), DateTime(2026, 2, 10));
    });

    test('handles a multi-year remaining balance', () {
      // 400 days remaining + 1 year. Display estimate; backend chains the defer.
      final next = projectedRenewal(from, 400, 'P1Y');
      expect(next.isAfter(DateTime(2028)), isTrue);
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
