import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/auth/payment/data/marketing_offers.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';

RaynOffer _storeOffer(String basePlanId) => RaynOffer(
      basePlanId: basePlanId,
      offerToken: '$basePlanId-base',
      formattedPrice: '\$0.00',
      priceAmountMicros: 0,
      priceCurrencyCode: 'USD',
      billingPeriodIso: 'P1M',
      isTrial: false,
    );

void main() {
  group('marketing screenshot offers', () {
    test('is off unless the build asked for it', () {
      // The guard that matters. These prices are asserted, not fetched, so a
      // shipped build showing them would be a lie told on the paywall — and
      // unlike the pinned latency it is a lie about money.
      expect(Constants.marketingScreenshots, isFalse);
      expect(pinOffersForMarketing(const []), isEmpty);
      expect(pinConnStateForMarketing(BillingConnState.unavailable), BillingConnState.unavailable);
      expect(pinConnStateForMarketing(BillingConnState.disabled), BillingConnState.disabled);
    });

    test('leaves the store answer alone when off', () {
      final offers = [_storeOffer('monthly')];
      expect(identical(pinOffersForMarketing(offers), offers), isTrue);
    });

    // Everything below tests `marketingOffers()` directly. The gate is a const
    // false in a test host, so the branch that substitutes them cannot be
    // reached from here — but the offers themselves can, and they are where the
    // mistakes would be.

    test('the display price and the amount it divides cannot drift', () {
      // Each price is written twice, because that is the shape both store APIs
      // return: `formattedPrice` is what the card prints, `priceAmountMicros`
      // is what the "Just $X/mo" line divides. Editing one and not the other
      // puts two disagreeing prices on the same card.
      for (final offer in marketingOffers()) {
        final digits = RegExp(r'[\d.]+').stringMatch(offer.formattedPrice);
        expect(digits, isNotNull, reason: '${offer.basePlanId} has no number in its display price');
        expect(
          double.parse(digits!),
          offer.priceAmountMicros / 1000000,
          reason: '${offer.basePlanId} displays $digits but carries ${offer.priceAmountMicros} micros',
        );
      }
    });

    test('carries the three prices the store listing quotes', () {
      final byPlan = {for (final o in marketingOffers()) o.basePlanId: o.formattedPrice};
      expect(byPlan, {'monthly': r'$19.99', 'quarter': r'$47.99', 'annual': r'$179.99'});
    });

    test('survives both reducers unchanged, in plan order', () {
      // reduceStoreOffers prefers a trial per base plan and reduceUpgradeOffers
      // prefers the non-trial one. With no trial in the list the two purchase
      // screens must show the same three cards in the same order.
      const order = ['monthly', 'quarter', 'annual'];
      expect(marketingOffers().map((o) => o.basePlanId), order);
      expect(reduceStoreOffers(marketingOffers()).map((o) => o.basePlanId), order);
      expect(reduceUpgradeOffers(marketingOffers()).map((o) => o.basePlanId), order);
      expect(marketingOffers().every((o) => !o.isTrial), isTrue);
    });

    test('the billing periods drive the right per-month line', () {
      final offers = marketingOffers();
      expect(offers.map((o) => o.billingPeriodIso), ['P1M', 'P3M', 'P1Y']);
      expect(offers.map((o) => periodMonths(o.billingPeriodIso)), [1, 3, 12]);

      // Monthly hides the line; the other two show it. Asserted as cents rather
      // than as formatted text, which depends on the host locale.
      expect(perMonthEquivalent(offers[0]), isNull);
      for (final offer in offers.skip(1)) {
        expect(perMonthEquivalent(offer), isNotNull);
        final cents = (offer.priceAmountMicros / 1000000 / periodMonths(offer.billingPeriodIso) * 100).round();
        expect(cents, offer.basePlanId == 'quarter' ? 1600 : 1500);
      }
    });

    test('every fabricated offer is identifiable, and a real one is not', () {
      expect(marketingOffers().every(isMarketingOffer), isTrue);
      expect(isMarketingOffer(_storeOffer('monthly')), isFalse);
    });
  });
}
