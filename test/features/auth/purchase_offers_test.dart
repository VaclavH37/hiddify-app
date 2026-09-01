import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';

RaynOffer _offer(String basePlanId, {String? offerId, bool isTrial = false, String token = ''}) => RaynOffer(
      basePlanId: basePlanId,
      offerId: offerId,
      offerToken: token.isEmpty ? '$basePlanId-${offerId ?? 'base'}' : token,
      formattedPrice: '\$0.00',
      priceAmountMicros: 0,
      priceCurrencyCode: 'USD',
      billingPeriodIso: 'P1M',
      isTrial: isTrial,
    );

void main() {
  group('reduceStoreOffers', () {
    test('orders the base plans monthly → quarter → annual regardless of input order', () {
      final result = reduceStoreOffers([_offer('annual'), _offer('monthly'), _offer('quarter')]);
      expect(result.map((o) => o.basePlanId), ['monthly', 'quarter', 'annual']);
    });

    test('keeps one offer per base plan, preferring the trial offer', () {
      // Play returns both the plain monthly base plan and its trial offer.
      final result = reduceStoreOffers([
        _offer('monthly', token: 'monthly-base'),
        _offer('monthly', offerId: 'trial', isTrial: true, token: 'monthly-trial'),
        _offer('quarter', token: 'quarter-base'),
        _offer('annual', token: 'annual-base'),
      ]);

      expect(result.map((o) => o.basePlanId), ['monthly', 'quarter', 'annual']);
      final monthly = result.firstWhere((o) => o.basePlanId == 'monthly');
      expect(monthly.isTrial, isTrue);
      expect(monthly.offerToken, 'monthly-trial');
    });

    test('prefers the trial even when it arrives before the base plan', () {
      final result = reduceStoreOffers([
        _offer('monthly', offerId: 'trial', isTrial: true, token: 'monthly-trial'),
        _offer('monthly', token: 'monthly-base'),
      ]);
      expect(result, hasLength(1));
      expect(result.single.offerToken, 'monthly-trial');
    });

    test('keeps the base plan when no trial offer exists', () {
      final result = reduceStoreOffers([_offer('quarter', token: 'quarter-base')]);
      expect(result.single.offerToken, 'quarter-base');
      expect(result.single.isTrial, isFalse);
    });

    test('places unknown base plans after the known ones', () {
      final result = reduceStoreOffers([_offer('weekly'), _offer('annual'), _offer('monthly')]);
      expect(result.map((o) => o.basePlanId), ['monthly', 'annual', 'weekly']);
    });

    test('empty in → empty out', () {
      expect(reduceStoreOffers([]), isEmpty);
    });
  });
}
