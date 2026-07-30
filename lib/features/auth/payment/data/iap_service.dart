import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/link_parsers.dart';
import 'package:hiddify/utils/rayn_token.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'iap_service.g.dart';

/// What the UI/notifier should do after a purchase attempt settles. One purchase
/// is in flight at a time, so a single broadcast stream of these is enough for
/// the notifier to react without correlating ids.
enum IapPurchaseOutcome {
  /// Verified + the `rayn://` cryptolink imported → go to /home.
  imported,

  /// Verify succeeded; the backend is still provisioning the subscription (the
  /// remnawave user + cryptolink are created by a ~30s outbox worker). Show the
  /// "activating your account" screen while we poll for the link to become
  /// importable. A terminal outcome ([imported] / [stillProvisioning]) follows.
  activating,

  /// Play returned PENDING (SCA / slow card) — show "payment processing"; the
  /// real result arrives in a later [RaynBillingEvents.onPurchasesUpdated].
  pendingPayment,

  /// User dismissed the Play sheet.
  canceled,

  /// `403 ACCOUNT_MISMATCH` — the purchase belongs to a different account.
  accountMismatch,

  /// `409 TOKEN_IN_USE` — the token already funds another account.
  tokenInUse,

  /// `403 INELIGIBLE` — account can't be granted yet (e.g. email unverified).
  ineligible,

  /// `401` or no stored session — the user must sign in again before verifying.
  needsLogin,

  /// `401 REAUTH_REQUIRED` on the cryptolink fetch — session older than 15 min;
  /// the UI must prompt for the password and re-auth before importing.
  reauthRequired,

  /// `429` — backend verify rate limit (5/user/min). Back off and retry.
  rateLimited,

  /// The API host couldn't be reached (transport failure).
  unreachable,

  /// The cryptolink's envelope version is one this build can't open. The
  /// purchase is safe — an updated app imports it on the next Restore.
  updateRequired,

  /// Generic / `5xx`. The purchase is safe; re-verify later (§5.5).
  failed,

  /// Verified, but the backend didn't finish provisioning the subscription
  /// (the remnawave user + cryptolink are created by a ~30s outbox worker)
  /// within our wait window. The purchase is safe — the link will be ready
  /// shortly, and the launch re-verify / Restore completes it.
  stillProvisioning,
}

/// Play `BillingResponseCode` values the purchase listener branches on.
abstract class _BillingResponse {
  static const ok = 0;
  static const userCanceled = 1;
  static const itemAlreadyOwned = 7;
}

@Riverpod(keepAlive: true)
IapService iapService(Ref ref) {
  final service = IapService(ref);
  ref.onDispose(service.dispose);
  return service;
}

/// Dart side of the Play Billing bridge. Owns the verify→import chain and turns
/// Play's async purchase events into [IapPurchaseOutcome]s the notifier consumes.
///
/// It does the Billing dance through the native [RaynBilling] host API and
/// listens for purchases by implementing [RaynBillingEvents]. The backend
/// acknowledges during verify, so this layer never acknowledges or grants access
/// off the local receipt — entitlement always follows the backend account state.
///
/// Android-only: [RaynBilling]/[RaynBillingEvents] have no desktop implementation,
/// so every native call is guarded by [_supported] and is inert elsewhere.
class IapService with InfraLogger implements RaynBillingEvents {
  IapService(this._ref) {
    if (_supported) {
      RaynBillingEvents.setUp(this);
    }
  }

  final Ref _ref;
  final RaynBilling _billing = RaynBilling();
  final StreamController<IapPurchaseOutcome> _outcomes = StreamController<IapPurchaseOutcome>.broadcast();

  bool get _supported => Platform.isAndroid;

  AuthApiClient get _client => _ref.read(authApiClientProvider);
  SessionTokenStore get _sessionStore => _ref.read(sessionTokenStoreProvider);

  /// Purchase results, pushed as each attempt settles. Broadcast so the notifier
  /// (and the re-verify-on-launch path) can both listen.
  Stream<IapPurchaseOutcome> get outcomes => _outcomes.stream;

  /// Connect the BillingClient. Returns [BillingConnState.unavailable] off-Android.
  Future<BillingConnState> connect() =>
      _supported ? _billing.connect() : Future<BillingConnState>.value(BillingConnState.unavailable);

  /// The subscription's offers (base plans + the trial). Empty off-Android.
  Future<List<RaynOffer>> loadOffers() =>
      _supported ? _billing.queryOffers(Constants.iapProductId) : Future<List<RaynOffer>>.value(const []);

  /// Launch the Play purchase sheet for [offer], binding it to this account via
  /// the stored `user_id` (`obfuscatedAccountId`). The returned [LaunchResult]
  /// only says whether the sheet opened; the purchase itself arrives via the
  /// event stream. Null off-Android.
  Future<LaunchResult?> buy(RaynOffer offer) async {
    if (!_supported) return null;
    final userId = await _sessionStore.readUserId();
    return _billing.launchPurchase(offer.offerToken, userId ?? '');
  }

  /// Re-discover active Play purchases and re-verify each (idempotent
  /// server-side). Covers acknowledgement-on-interrupted-verify, restore on
  /// reinstall, and login on a new device. Returns whether any active purchase
  /// was found (each pushes its result on [outcomes]).
  Future<bool> restore() async {
    if (!_supported) return false;
    final purchases = await _billing.queryActivePurchases();
    final active = purchases.where((p) => p.state == RaynPurchaseState.purchased).toList();
    for (final p in active) {
      _outcomes.add(await _verifyAndActivate(p));
    }
    return active.isNotEmpty;
  }

  // ---- RaynBillingEvents (native -> Dart) ----

  @override
  void onPurchasesUpdated(List<RaynPurchase> purchases, int responseCode) {
    unawaited(_handlePurchases(purchases, responseCode));
  }

  @override
  void onBillingDisconnected() {
    // Best-effort single reconnect; queries no-op until it's ready again.
    if (_supported) unawaited(_billing.connect());
  }

  Future<void> _handlePurchases(List<RaynPurchase> purchases, int responseCode) async {
    switch (responseCode) {
      case _BillingResponse.userCanceled:
        _outcomes.add(IapPurchaseOutcome.canceled);
        return;
      case _BillingResponse.itemAlreadyOwned:
        // Owned but not delivered in this update — reconcile via active purchases.
        await restore();
        return;
      case _BillingResponse.ok:
        for (final p in purchases) {
          await _settle(p);
        }
      default:
        loggy.warning("purchase update failed: response $responseCode");
        _outcomes.add(IapPurchaseOutcome.failed);
    }
  }

  Future<void> _settle(RaynPurchase purchase) async {
    switch (purchase.state) {
      case RaynPurchaseState.pending:
        _outcomes.add(IapPurchaseOutcome.pendingPayment);
      case RaynPurchaseState.unspecified:
        return; // not a real purchase yet — ignore.
      case RaynPurchaseState.purchased:
        _outcomes.add(await _verifyAndActivate(purchase));
    }
  }

  /// The subscription API a cryptolink points to returns 404 until the backend's
  /// activation outbox (a ~30s worker) provisions the remnawave user + link, so
  /// we poll the import a few times over ~a minute before giving up.
  static const _activationPollInterval = Duration(seconds: 30);
  static const _maxActivationAttempts = 3; // t = 0s, 30s, 60s.

  /// `POST /iap/google/verify`, then wait for provisioning and import the link.
  ///
  /// `verify` grants + acknowledges and returns the `rayn://` cryptolink, but the
  /// remnawave user + cryptolink are created asynchronously by a ~30s outbox
  /// worker, so the subscription API the link points to 404s until then. We emit
  /// [IapPurchaseOutcome.activating] (drives the "activating your account" screen)
  /// and poll the import until it succeeds ([imported]) or the window elapses
  /// ([stillProvisioning]).
  Future<IapPurchaseOutcome> _verifyAndActivate(RaynPurchase purchase) async {
    final token = await _sessionStore.read();
    if (token == null || token.isEmpty) return IapPurchaseOutcome.needsLogin;

    final String? cryptolink;
    try {
      final resp = await _client.post(
        '/iap/google/verify',
        {'purchaseToken': purchase.purchaseToken, 'productId': purchase.productId},
        bearer: token,
      );
      cryptolink = resp['subscription_url'] as String?;
    } on AuthApiException catch (e) {
      return _mapVerifyError(e);
    }

    // Entitlement applied — show the activating screen while provisioning finishes.
    _outcomes.add(IapPurchaseOutcome.activating);

    final link = (cryptolink != null && cryptolink.isNotEmpty) ? cryptolink : await _fetchCryptolink(token);
    if (link == null || link.isEmpty) return IapPurchaseOutcome.stillProvisioning;
    return _pollImport(link);
  }

  IapPurchaseOutcome _mapVerifyError(AuthApiException e) {
    if (e.isUnreachable) return IapPurchaseOutcome.unreachable;
    switch (e.code) {
      case 'ACCOUNT_MISMATCH':
        return IapPurchaseOutcome.accountMismatch;
      case 'TOKEN_IN_USE':
        return IapPurchaseOutcome.tokenInUse;
      case 'INELIGIBLE':
        return IapPurchaseOutcome.ineligible;
    }
    if (e.status == 401) return IapPurchaseOutcome.needsLogin;
    if (e.status == 429) return IapPurchaseOutcome.rateLimited;
    return IapPurchaseOutcome.failed;
  }

  /// Poll the import of [cryptolink] until the backend has provisioned the
  /// subscription it points to. Each attempt fetches the (decrypted) subscription
  /// API; while the activation outbox hasn't run, that API 404s and the import
  /// fails, so we wait [_activationPollInterval] and retry, up to
  /// [_maxActivationAttempts] (~1 minute total). Uses the repository directly
  /// (not [AddProfileNotifier]) so a transient failure doesn't pop an error
  /// dialog on every retry; on success the persisted profile drives the router
  /// redirect to `/home`.
  Future<IapPurchaseOutcome> _pollImport(String cryptolink) async {
    final RaynLinkOk parsed;
    switch (LinkParser.parse(cryptolink)) {
      case RaynLinkOk ok:
        parsed = ok;
      case RaynLinkUnsupportedVersion():
        // The purchase is safe; an updated build will import it on Restore.
        return IapPurchaseOutcome.updateRequired;
      case RaynLinkInvalid():
        return IapPurchaseOutcome.failed;
    }

    final repo = await _ref.read(profileRepositoryProvider.future);
    for (var attempt = 1; attempt <= _maxActivationAttempts; attempt++) {
      final result = await repo
          .upsertRemote(
            parsed.url,
            sourceToken: cryptolink,
          )
          .run();
      if (result.isRight()) return IapPurchaseOutcome.imported;
      loggy.debug("activation import attempt $attempt/$_maxActivationAttempts not ready yet");
      if (attempt < _maxActivationAttempts) await Future<void>.delayed(_activationPollInterval);
    }
    return IapPurchaseOutcome.stillProvisioning;
  }

  /// Fallback fetch of the cryptolink when `verify` didn't return it inline.
  Future<String?> _fetchCryptolink(String bearer) async {
    try {
      final r = await _client.get('/api/public/account/subscription', bearer: bearer);
      return r['subscription_url'] as String?;
    } on AuthApiException catch (e) {
      loggy.debug("cryptolink fetch failed: ${e.status} ${e.code}");
      return null;
    }
  }

  void dispose() {
    if (_supported) {
      RaynBillingEvents.setUp(null);
      unawaited(_billing.endConnection());
    }
    unawaited(_outcomes.close());
  }
}
