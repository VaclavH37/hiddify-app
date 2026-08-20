// Pigeon contract for the in-app purchase bridge: Google Play Billing on
// Android, StoreKit 2 on iOS.
//
// This is a CODEGEN INPUT, not shipped code: `dart run pigeon --input
// pigeons/rayn_billing.dart` regenerates the Dart, Kotlin and Swift glue
// listed in the @ConfigurePigeon block. Never hand-edit the generated
// *.g.dart / *.g.kt / *.g.swift.
//
// Design (see IAP_Integration/IAP-CLIENT-INTEGRATION.md + the
// project_iap_client_integration memory):
//   * Dart owns verify / import / session / UI; the native side does ONLY the
//     store dance and never persists state.
//   * Two directions: @HostApi = Dart asks native (connect/query/launch);
//     @FlutterApi = native pushes the store's purchase events up to Dart.
//   * There is deliberately NO acknowledge method — the BACKEND acknowledges
//     during verify. Omitting it makes "client never acknowledges" structural.
//     `finishPurchase` is not an exception: on Apple, StoreKit redelivers an
//     unfinished transaction forever, so finishing it is how the client says
//     "delivered", not "entitled". Dart calls it only after the backend has
//     returned 200, and the Play implementation is a no-op.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/features/auth/payment/data/rayn_billing.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/raynlabs/app/billing/RaynBilling.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.raynlabs.app.billing'),
    swiftOut: 'ios/Runner/Billing/RaynBilling.g.swift',
    dartPackageName: 'hiddify',
  ),
)
// Result of connecting to the store.
enum BillingConnState {
  /// Connected and ready to query/purchase.
  connected,

  /// Play Billing is unavailable on this device (no Play Store / unsupported).
  /// Not reachable on iOS — StoreKit is always present.
  unavailable,

  /// Purchasing is disabled: Play reports the feature unsupported, or Apple's
  /// `AppStore.canMakePayments` is false (e.g. parental restrictions).
  disabled,
}

// Mirrors Play `Purchase.PurchaseState`. On Apple every delivered `Transaction`
// is [purchased]; [pending] is synthesised from a `.pending` purchase result
// (Ask-to-Buy / SCA), which carries no transaction yet.
enum RaynPurchaseState { purchased, pending, unspecified }

/// One purchasable offer derived from `ProductDetails.subscriptionOfferDetails`
/// — i.e. a base plan, or an offer (the free trial) attached to a base plan.
class RaynOffer {
  RaynOffer({
    required this.basePlanId,
    this.offerId,
    required this.offerToken,
    required this.formattedPrice,
    required this.priceAmountMicros,
    required this.priceCurrencyCode,
    required this.billingPeriodIso,
    required this.isTrial,
  });

  /// "monthly" | "quarter" | "annual" — Play Console base-plan IDs, and on
  /// Apple the suffix of the per-tier product id (`rayn_premium_monthly`).
  final String basePlanId;

  /// Offer id (e.g. "trial"); null for the plain base plan with no offer.
  final String? offerId;

  /// Opaque token passed verbatim to `launchPurchase` — selects this exact
  /// base-plan/offer in the billing flow. Play: the `offerToken`. Apple: the
  /// product id, which is what resolves back to a `Product`.
  final String offerToken;

  /// Localized, currency-correct price for display, e.g. "$19.99" / "₹1,699.00".
  final String formattedPrice;

  /// Price in micros (1,000,000 = one unit) for computing per-month equivalents.
  final int priceAmountMicros;

  /// ISO-4217 code, e.g. "USD".
  final String priceCurrencyCode;

  /// ISO-8601 billing period of the recurring phase: "P1M" | "P3M" | "P1Y".
  final String billingPeriodIso;

  /// Whether this offer leads with a free-trial phase (priceAmountMicros == 0).
  final bool isTrial;
}

/// A Play `Purchase` reduced to what the backend verify call needs.
class RaynPurchase {
  RaynPurchase({
    required this.purchaseToken,
    required this.productId,
    required this.state,
    required this.isAcknowledged,
  });

  /// The store's opaque identifier for this purchase, sent to the backend's
  /// verify endpoint. Play: `Purchase.getPurchaseToken()`, posted as
  /// `purchaseToken`. Apple: `String(Transaction.id)`, posted as
  /// `transactionId` — a JSON STRING; encoding Apple's `UInt64` as a number
  /// is a 400.
  final String purchaseToken;

  /// The subscription product id: `rayn_premium` on Play (one product carrying
  /// every base plan), or the per-tier id on Apple (`rayn_premium_monthly`).
  final String productId;

  final RaynPurchaseState state;

  /// Already settled server-side. Play: the backend acknowledged it. Apple: we
  /// already called [RaynBilling.finishPurchase], which only ever happens after
  /// a backend 200 — so the meaning carries. Lets the re-verify loop skip
  /// purchases that are already bound.
  final bool isAcknowledged;
}

/// Synchronous result of `launchBillingFlow` — only reports whether the sheet
/// opened. The actual purchase arrives later via [RaynBillingEvents].
class LaunchResult {
  LaunchResult({required this.responseCode, this.debugMessage});

  /// Play `BillingResponseCode` (0 = OK, 1 = USER_CANCELED, 7 = ITEM_ALREADY
  /// _OWNED, …). The Apple host deliberately emits these same integers, so the
  /// Dart layer needs no per-store branching.
  final int responseCode;

  final String? debugMessage;
}

/// Dart -> Kotlin. Calls we initiate against the BillingClient.
@HostApi()
abstract class RaynBilling {
  /// Build + connect the BillingClient (idempotent; reconnects if dropped).
  @async
  BillingConnState connect();

  /// Query the purchasable offers for [productId].
  ///
  /// Play: one product (`rayn_premium`) carrying the base plans plus the trial
  /// offer. Apple: [productId] names the subscription GROUP, which the host
  /// expands into one product per base plan (`<productId>_<basePlanId>`) and
  /// returns a single offer for each.
  @async
  List<RaynOffer> queryOffers(String productId);

  /// Launch the purchase UI for [offerToken], binding the purchase to the
  /// account: Play `setObfuscatedAccountId`, Apple `.appAccountToken`. Both
  /// take the raw lowercase RouteKey `user_id`; Apple additionally requires it
  /// to parse as a UUID, and the host omits the option rather than send a
  /// fabricated value. Not @async — it returns immediately; the purchase
  /// comes back through [RaynBillingEvents].
  LaunchResult launchPurchase(String offerToken, String obfuscatedAccountId);

  /// Active subscription purchases — drives re-verify-on-launch and
  /// restore-on-reinstall. Play: `queryPurchasesAsync`. Apple: the union of
  /// `Transaction.currentEntitlements` and `Transaction.unfinished`, so an
  /// interrupted verify is replayed as well as a reinstall.
  @async
  List<RaynPurchase> queryActivePurchases();

  /// Tell the store this purchase has been delivered.
  ///
  /// Apple-only in effect. StoreKit redelivers an unfinished transaction
  /// forever, so it has to be finished once the BACKEND has confirmed it —
  /// this is delivery confirmation, NOT acknowledgement, and entitlement still
  /// follows the backend. Dart calls it from exactly one place: immediately
  /// after `verify` returns 200. Play never acknowledges locally, so its
  /// implementation is a deliberate no-op.
  void finishPurchase(String purchaseToken);

  /// Tear down the store connection (e.g. on logout / app dispose).
  void endConnection();
}

/// Kotlin -> Dart. Play's asynchronous push events.
@FlutterApi()
abstract class RaynBillingEvents {
  /// From `PurchasesUpdatedListener`. Dart verifies PURCHASED items, shows
  /// "processing" for PENDING, and resets the UI on USER_CANCELED.
  void onPurchasesUpdated(List<RaynPurchase> purchases, int responseCode);

  /// From `onBillingServiceDisconnected` — Dart may trigger a reconnect. Never
  /// fired on iOS; StoreKit has no connection to lose.
  void onBillingDisconnected();
}
