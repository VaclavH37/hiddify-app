import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';

/// Localized message for a settled [IapPurchaseOutcome].
///
/// Shared because three surfaces report a purchase result — the sign-up
/// paywall's inline error, the plan-transition upsell's inline error, and the
/// Restore toast in Settings → Account. It lived as two private copies, and
/// they had already drifted: the upsell's copy was missing
/// [IapPurchaseOutcome.updateRequired], so a purchase this build can't open
/// showed the generic failure there and the specific "update the app" message
/// on the paywall. One copy makes that impossible rather than merely unlikely.
///
/// Unmapped outcomes fall through to the generic error, so a new enum value is
/// never rendered blank.
String iapOutcomeMessage(Translations t, IapPurchaseOutcome? outcome) {
  switch (outcome) {
    case IapPurchaseOutcome.accountMismatch:
      return t.auth.payment.errorAccountMismatch;
    case IapPurchaseOutcome.tokenInUse:
      return t.auth.payment.errorTokenInUse;
    case IapPurchaseOutcome.ineligible:
      return t.auth.payment.errorIneligible;
    case IapPurchaseOutcome.familyShared:
      return t.auth.payment.errorFamilyShared;
    case IapPurchaseOutcome.needsLogin:
      return t.auth.payment.errorNeedsLogin;
    case IapPurchaseOutcome.reauthRequired:
      return t.auth.payment.errorReauth;
    case IapPurchaseOutcome.stillProvisioning:
      return t.auth.payment.errorProvisioning;
    case IapPurchaseOutcome.rateLimited:
      return t.auth.payment.errorRateLimited;
    case IapPurchaseOutcome.unreachable:
      return t.auth.payment.errorUnreachable;
    case IapPurchaseOutcome.updateRequired:
      return t.auth.payment.errorUpdateRequired;
    default:
      return t.auth.payment.errorGeneric;
  }
}
