/// Which system bills the subscription. The value arrives verbatim from the
/// middleware as the `subscription-payment-provider` response header on the
/// subscription fetch and is persisted in `RemoteProfileEntity.populatedHeaders`
/// — the client has no other source for it, and never calls `/api/public/account`.
///
/// The backend's full set is `app_store`, `google_play`, `nowpayments`,
/// `guardarian`, `trial` and `admin`. Only the store-managed pair below is
/// matched here; everything else, including an unrecognised future value, falls
/// through to the non-auto-renewing behaviour, which is the safe default.
library;

/// Whether the subscription renews itself through an app store.
///
/// Three behaviours hang off this, and all three are wrong for a store-managed
/// plan if it returns false:
///  - the `expire` date is a *renewal* date, not an expiry date;
///  - renewal is automatic, so we show one heads-up rather than a 7-day
///    expiry countdown;
///  - a "Manage subscription" deep link exists, and offering a *second* store
///    subscription would charge the user twice for the same account — neither
///    store will refund that on our behalf.
///
/// Deliberately not an enum: the middleware owns this vocabulary, and an
/// unknown string must degrade to "not store-managed" rather than throw.
bool isStoreManagedProvider(String? provider) => provider == 'google_play' || provider == 'app_store';

/// The store's auto-renew flag from the `subscription-auto-renew` config
/// header: `true`, `false`, or null for anything else.
///
/// ABSENT MEANS UNKNOWN, never false. The header is missing until the backend
/// ships the field, and for up to a minute afterwards while the middleware's
/// cache turns over; reading that as "cancelled" would show every
/// auto-renewing subscriber an end date and send them lapse warnings. Callers
/// keep today's behaviour on null.
bool? autoRenewFromHeader(String? value) => switch (value?.trim().toLowerCase()) {
  'true' => true,
  'false' => false,
  _ => null,
};

/// Whether the plan will renew itself: store-managed and not switched off.
/// An unknown flag keeps a store plan on the auto-renewing path.
bool renewsItself({required String? provider, required bool? autoRenew}) =>
    isStoreManagedProvider(provider) && autoRenew != false;
