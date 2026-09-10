import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:meta/meta.dart';

/// Prices a screenshots build shows on the paywall, in micros — the unit
/// [RaynOffer.priceAmountMicros] uses, where 1,000,000 is one currency unit.
///
/// Keep these equal to the price points configured in App Store Connect and
/// the Play Console. The screenshot they produce is what a reviewer compares
/// the configured price against.
const marketingPriceMonthlyMicros = 19990000;
const marketingPriceQuarterMicros = 47990000;
const marketingPriceAnnualMicros = 179990000;

/// Marks an offer as fabricated. Prefixes [RaynOffer.offerToken], which is
/// otherwise the Play offer token or the Apple product id — an opaque string
/// handed straight back to the store by `launchPurchase`.
///
/// No store knows these tokens, so [isMarketingOffer] is what keeps the one
/// caller that would pass one along from trying.
const marketingOfferTokenPrefix = "marketing:";

/// Whether [offer] came from [marketingOffers] rather than from a store.
bool isMarketingOffer(RaynOffer offer) => offer.offerToken.startsWith(marketingOfferTokenPrefix);

/// The three plans a screenshots build offers, in the order `PurchaseNotifier`
/// sorts real ones into: monthly, quarter, annual.
///
/// `isTrial: false` on all three, for two reasons. `reduceStoreOffers` keeps
/// the trial when a base plan has both and `reduceUpgradeOffers` keeps the
/// non-trial one, so a list with no trial in it survives either reducer
/// unchanged and both purchase screens show the same cards. And no
/// introductory offer is configured on either store, so a "Free trial" badge
/// would promise something no purchase could deliver.
///
/// The prices are written twice on purpose — once as display text, once as the
/// amount `perMonthEquivalent` divides — because that is the shape the store
/// APIs return. `marketing_offers_test.dart` ties the two together.
List<RaynOffer> marketingOffers() => [
      RaynOffer(
        basePlanId: "monthly",
        offerToken: "${marketingOfferTokenPrefix}monthly",
        formattedPrice: r"$19.99",
        priceAmountMicros: marketingPriceMonthlyMicros,
        priceCurrencyCode: "USD",
        billingPeriodIso: "P1M",
        isTrial: false,
      ),
      RaynOffer(
        basePlanId: "quarter",
        offerToken: "${marketingOfferTokenPrefix}quarter",
        formattedPrice: r"$47.99",
        priceAmountMicros: marketingPriceQuarterMicros,
        priceCurrencyCode: "USD",
        billingPeriodIso: "P3M",
        isTrial: false,
      ),
      RaynOffer(
        basePlanId: "annual",
        offerToken: "${marketingOfferTokenPrefix}annual",
        formattedPrice: r"$179.99",
        priceAmountMicros: marketingPriceAnnualMicros,
        priceCurrencyCode: "USD",
        billingPeriodIso: "P1Y",
        isTrial: false,
      ),
    ];

/// Completes the paywall with whatever the store did not return.
///
/// Applied where the store's answer enters the app rather than in the widgets,
/// so both purchase screens agree: the sign-up paywall (`PaymentPage`) and the
/// web-to-store upgrade page (`PlanTransitionPage`) share `PurchaseNotifier`,
/// and it is that notifier which turns an empty list into
/// `PurchaseState.unavailable` and the "In-app purchases unavailable" card.
///
/// **Never distribute a build with [Constants.marketingScreenshots] set.** The
/// prices above are asserted, not fetched: not localized, not in the user's
/// currency, and not necessarily what the store would charge.
///
/// In a normal build that constant is a `const false`, so this is an identity
/// function the tree shaker removes.
List<RaynOffer> pinOffersForMarketing(List<RaynOffer> offers) =>
    Constants.marketingScreenshots ? withMissingPlansFilledIn(offers) : offers;

/// [offers], plus a fabricated one for every base plan missing from it.
///
/// Per plan, not all-or-nothing, because a store populates one product at a
/// time. Submitting subscriptions to App Store Connect means the products
/// become visible to `Product.products(for:)` as each reaches "Ready to
/// Submit", so the realistic state is a *partial* answer — one real monthly and
/// nothing else — and a rule that only replaced a completely empty list left
/// that showing a single card.
///
/// A real offer always wins for its own plan. Once all three are live this
/// returns [offers] untouched and the whole thing retires itself.
///
/// Order is not fixed here: `reduceStoreOffers` and `reduceUpgradeOffers` both
/// sort by base plan afterwards, which is also what dedupes if a store ever
/// returns two offers for one plan.
///
/// The one thing to watch when the answer is partial: the fabricated prices are
/// US dollars, so a device on another storefront gets a real price in its own
/// currency beside two placeholders in USD. Capture on the US storefront.
@visibleForTesting
List<RaynOffer> withMissingPlansFilledIn(List<RaynOffer> offers) {
  final present = offers.map((o) => o.basePlanId).toSet();
  final missing = marketingOffers().where((o) => !present.contains(o.basePlanId)).toList();
  return missing.isEmpty ? offers : [...offers, ...missing];
}

/// Reports the store as reachable in a screenshots build.
///
/// Without this a desktop capture never reaches the offers at all: `IapService`
/// supports Android and iOS only, so `connect()` answers `unavailable` on
/// Windows and `PurchaseNotifier._init()` stops on that before querying
/// anything. On a handset it is a no-op in practice — the only thing that makes
/// a healthy device report anything but `connected` is a payment restriction.
BillingConnState pinConnStateForMarketing(BillingConnState state) =>
    Constants.marketingScreenshots ? BillingConnState.connected : state;
