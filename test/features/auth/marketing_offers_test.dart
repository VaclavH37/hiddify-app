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

    // The gate is a const false in a test host, so `pinOffersForMarketing`
    // cannot be seen doing anything from here. Its logic lives in
    // `withMissingPlansFilledIn`, which reads no gate and is tested directly.

    group('withMissingPlansFilledIn', () {
      test('an empty answer becomes all three plans', () {
        expect(withMissingPlansFilledIn(const []).map((o) => o.basePlanId), ['monthly', 'quarter', 'annual']);
      });

      test('fills in only what the store did not return, keeping the real offer', () {
        // The state App Store Connect leaves you in while submitting: monthly
        // is Ready to Submit and returns from Product.products(for:), the other
        // two do not exist yet. A rule that only replaced an *empty* answer
        // showed one card here.
        final real = _storeOffer('monthly');
        final filled = withMissingPlansFilledIn([real]);

        expect(filled.length, 3);
        expect(filled.where((o) => o.basePlanId == 'monthly').single, same(real));
        expect(filled.where(isMarketingOffer).map((o) => o.basePlanId), ['quarter', 'annual']);
      });

      test('the reducers sort a part-real answer back into plan order', () {
        // Nothing above fixes the order, so this is what the paywall relies on.
        final filled = withMissingPlansFilledIn([_storeOffer('annual')]);
        expect(reduceStoreOffers(filled).map((o) => o.basePlanId), ['monthly', 'quarter', 'annual']);
        expect(reduceUpgradeOffers(filled).map((o) => o.basePlanId), ['monthly', 'quarter', 'annual']);
      });

      test('a complete answer is returned untouched, so real prices always win', () {
        final real = [_storeOffer('monthly'), _storeOffer('quarter'), _storeOffer('annual')];
        expect(identical(withMissingPlansFilledIn(real), real), isTrue);
        expect(withMissingPlansFilledIn(real).any(isMarketingOffer), isFalse);
      });
    });

    // Everything below tests `marketingOffers()` directly — the offers
    // themselves are where the mistakes would be.

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
