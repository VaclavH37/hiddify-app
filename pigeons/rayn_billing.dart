// Pigeon contract for the Google Play Billing bridge.
//
// This is a CODEGEN INPUT, not shipped code: `dart run pigeon --input
// pigeons/rayn_billing.dart` regenerates the Dart and Kotlin glue listed in
// the @ConfigurePigeon block. Never hand-edit the generated *.g.dart / *.g.kt.
//
// Design (see IAP_Integration/IAP-CLIENT-INTEGRATION.md + the
// project_iap_client_integration memory):
//   * Dart owns verify / import / session / UI; the native side does ONLY the
//     Play Billing dance and never persists state.
//   * Two directions: @HostApi = Dart asks native (connect/query/launch);
//     @FlutterApi = native pushes Play's async purchase events up to Dart.
//   * There is deliberately NO acknowledge method — the BACKEND acknowledges
//     during verify. Omitting it makes "client never acknowledges" structural.
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/features/auth/payment/data/rayn_billing.g.dart',
    kotlinOut: 'android/app/src/main/kotlin/com/raynlabs/app/billing/RaynBilling.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.raynlabs.app.billing'),
    dartPackageName: 'hiddify',
  ),
)
// Result of connecting the BillingClient.
enum BillingConnState {
  /// Connected and ready to query/purchase.
  connected,

  /// Play Billing is unavailable on this device (no Play Store / unsupported).
  unavailable,

  /// Billing is disabled (e.g. feature not supported / region).
  disabled,
}

// Mirrors Play `Purchase.PurchaseState`.
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

  /// "monthly" | "quarter" | "annual" (Play Console base-plan IDs).
  final String basePlanId;

  /// Offer id (e.g. "trial"); null for the plain base plan with no offer.
  final String? offerId;

  /// Opaque token passed verbatim to `launchPurchase` — selects this exact
  /// base-plan/offer in the billing flow.
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

  /// `Purchase.getPurchaseToken()` — sent to `POST /iap/google/verify`.
  final String purchaseToken;

  /// The subscription product id, e.g. "rayn_premium".
  final String productId;

  final RaynPurchaseState state;

  /// Already settled server-side (backend acknowledged it). Lets the re-verify
  /// loop skip purchases that are already bound.
  final bool isAcknowledged;
}

/// Synchronous result of `launchBillingFlow` — only reports whether the sheet
/// opened. The actual purchase arrives later via [RaynBillingEvents].
class LaunchResult {
  LaunchResult({required this.responseCode, this.debugMessage});

  /// Play `BillingResponseCode` (0 = OK, 1 = USER_CANCELED, …).
  final int responseCode;

  final String? debugMessage;
}

/// Dart -> Kotlin. Calls we initiate against the BillingClient.
@HostApi()
abstract class RaynBilling {
  /// Build + connect the BillingClient (idempotent; reconnects if dropped).
  @async
  BillingConnState connect();

  /// Query the subscription product's offers (base plans + the trial offer).
  @async
  List<RaynOffer> queryOffers(String productId);

  /// Launch the purchase UI for [offerToken], binding the purchase to the
  /// account via `setObfuscatedAccountId(obfuscatedAccountId)`. Not @async —
  /// it returns immediately; the purchase comes back through [RaynBillingEvents].
  LaunchResult launchPurchase(String offerToken, String obfuscatedAccountId);

  /// Active SUBS purchases (`queryPurchasesAsync`) — drives re-verify-on-launch
  /// and restore-on-reinstall.
  @async
  List<RaynPurchase> queryActivePurchases();

  /// Tear down the BillingClient (e.g. on logout / app dispose).
  void endConnection();
}

/// Kotlin -> Dart. Play's asynchronous push events.
@FlutterApi()
abstract class RaynBillingEvents {
  /// From `PurchasesUpdatedListener`. Dart verifies PURCHASED items, shows
  /// "processing" for PENDING, and resets the UI on USER_CANCELED.
  void onPurchasesUpdated(List<RaynPurchase> purchases, int responseCode);

  /// From `onBillingServiceDisconnected` — Dart may trigger a reconnect.
  void onBillingDisconnected();
}
