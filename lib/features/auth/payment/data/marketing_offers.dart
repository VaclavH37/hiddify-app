import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';

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

/// Fills the paywall in when the store answered with nothing.
///
/// Applied where the store's answer enters the app rather than in the widgets,
/// so both purchase screens agree: the sign-up paywall (`PaymentPage`) and the
/// web-to-store upgrade page (`PlanTransitionPage`) share `PurchaseNotifier`,
/// and it is that notifier which turns an empty list into
/// `PurchaseState.unavailable` and the "In-app purchases unavailable" card.
///
/// Only fills a vacuum. A non-empty list is returned untouched even with the
/// gate on, so once the products go live the real, store-localized prices win
/// and this retires itself.
///
/// **Never distribute a build with [Constants.marketingScreenshots] set.** The
/// prices above are asserted, not fetched: not localized, not in the user's
/// currency, and not necessarily what the store would charge.
///
/// In a normal build that constant is a `const false`, so this is an identity
/// function the tree shaker removes.
List<RaynOffer> pinOffersForMarketing(List<RaynOffer> offers) {
  if (!Constants.marketingScreenshots) return offers;
  if (offers.isNotEmpty) return offers;
  return marketingOffers();
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
