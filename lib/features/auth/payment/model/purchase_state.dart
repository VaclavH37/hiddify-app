import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';

enum PurchaseStatus {
  /// Connecting + querying offers.
  loading,

  /// Billing not available (no Play / unsupported) or no offers returned.
  unavailable,

  /// Offers loaded; idle and ready to buy.
  ready,

  /// A purchase/restore is in flight (launch + verify).
  busy,

  /// Verified; the backend is provisioning the subscription (~30s outbox). Shows
  /// a full-screen "activating your account" loading view while we poll.
  activating,

  /// Play returned PENDING — payment is processing out of band.
  processing,

  /// Verified + imported; the router redirect swaps to /home.
  success,

  /// A purchase attempt failed; [PurchaseState.outcome] carries which.
  error,
}

/// Sentinel so [PurchaseState.copyWith] can distinguish "leave as-is" from
/// "set to null" for the nullable fields.
const Object _keep = Object();

class PurchaseState {
  const PurchaseState({
    required this.status,
    this.offers = const [],
    this.outcome,
    this.pendingOfferToken,
  });

  final PurchaseStatus status;

  /// One display offer per base plan (trial preferred), ordered for display.
  final List<RaynOffer> offers;

  /// Set when [status] is [PurchaseStatus.error] — maps to the inline message.
  final IapPurchaseOutcome? outcome;

  /// The offerToken currently being purchased (its card shows a spinner).
  final String? pendingOfferToken;

  static const loading = PurchaseState(status: PurchaseStatus.loading);
  static const unavailable = PurchaseState(status: PurchaseStatus.unavailable);

  bool get isBusy => status == PurchaseStatus.busy;

  PurchaseState copyWith({
    PurchaseStatus? status,
    List<RaynOffer>? offers,
    Object? outcome = _keep,
    Object? pendingOfferToken = _keep,
  }) {
    return PurchaseState(
      status: status ?? this.status,
      offers: offers ?? this.offers,
      outcome: outcome == _keep ? this.outcome : outcome as IapPurchaseOutcome?,
      pendingOfferToken: pendingOfferToken == _keep ? this.pendingOfferToken : pendingOfferToken as String?,
    );
  }
}
