import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/payment/data/marketing_offers.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/auth/payment/model/verify_verdict.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
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

  /// The store returned PENDING (Apple Ask-to-Buy / SCA, Play slow card) —
  /// show "payment processing"; the real result arrives in a later
  /// [RaynBillingEvents.onPurchasesUpdated].
  pendingPayment,

  /// User dismissed the purchase sheet.
  canceled,

  /// `403 ACCOUNT_MISMATCH` — the purchase belongs to a different account.
  accountMismatch,

  /// `409 TOKEN_IN_USE` — the token already funds another account.
  tokenInUse,

  /// `403 INELIGIBLE` — account can't be granted yet (e.g. email unverified).
  ineligible,

  /// `403 FAMILY_SHARED` — an Apple Family Sharing entitlement. The purchase
  /// belongs to the family organiser, not this user, so `appAccountToken` can
  /// never match. Unrecoverable on this device: retrying never helps, so this
  /// gets its own explained end state rather than a generic failure.
  familyShared,

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

  /// The store redelivered, or Restore found, a transaction this device has
  /// already verified and imported. Nothing to do: the notifier stays put, and
  /// a Restore tap reads it as restored.
  alreadySettled,

  /// A verify 200 with `account_status: "expired"`: the subscription has ended
  /// and nothing was granted. Never "activating". The two variants carry the
  /// store's reason when it gave one, so the copy can say what to do — update
  /// the payment method, or nothing after a refund.
  ended,
  endedBillingRetry,
  endedRevoked,

  /// A verify 200 with another `account_status` (suspended, deactivated, …):
  /// the account cannot receive access, whatever was bought.
  accountUnavailable,

  /// A verify 200 with `account_status: "pending_activation"`: the verified
  /// subscription had ended, and the account is waiting on a web payment to
  /// settle. Nothing was granted; never "activating".
  accountPending,
}

/// Which store's backend contract this build talks to.
///
/// The purchase machinery is otherwise identical, so this selects only the
/// verify endpoint and the field name the purchase id travels under.
enum IapStore { googlePlay, appStore }

/// Play `BillingResponseCode` values the purchase listener branches on. The
/// Apple host deliberately emits the same integers, so nothing here is
/// Play-specific at runtime.
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

/// Dart side of the in-app purchase bridge. Owns the verify→import chain and
/// turns the store's async purchase events into [IapPurchaseOutcome]s the
/// notifier consumes.
///
/// It does the store dance through the native [RaynBilling] host API and
/// listens for purchases by implementing [RaynBillingEvents]. The backend
/// acknowledges during verify, so this layer never acknowledges or grants access
/// off the local receipt — entitlement always follows the backend account state.
/// Apple adds one step, [RaynBilling.finishSubscription]: it tells StoreKit to stop
/// redelivering a transaction the backend has already accepted. That is delivery
/// confirmation, not entitlement, and it happens only after a verify 200.
///
/// Mobile-only: [RaynBilling]/[RaynBillingEvents] have no desktop implementation,
/// so every native call is guarded by [_supported] and is inert elsewhere.
class IapService with InfraLogger implements RaynBillingEvents {
  /// [store], [billing] and [supported] exist so tests can exercise the Apple
  /// request shape and the finish-after-200 rule on a host where neither
  /// platform check is true. Production always takes the defaults.
  IapService(this._ref, {IapStore? store, RaynBilling? billing, bool? supported, List<Duration>? backoff})
    : _store = store ?? (Platform.isIOS ? IapStore.appStore : IapStore.googlePlay),
      _billing = billing ?? RaynBilling(),
      _supported = supported ?? (Platform.isAndroid || Platform.isIOS),
      _backoff = backoff ?? defaultBackoff {
    if (_supported) {
      RaynBillingEvents.setUp(this);
    }
  }

  final Ref _ref;
  final IapStore _store;
  final RaynBilling _billing;
  final StreamController<IapPurchaseOutcome> _outcomes = StreamController<IapPurchaseOutcome>.broadcast();

  /// Verify once per subscription (the backend's recommendations, §1–2).
  /// Several paths deliver the same purchase — the purchase result, the store's
  /// updates stream, a Restore tap, the launch replay — and every verify spends
  /// one of the five requests a minute the whole account shares with checkout
  /// and password changes; four for one purchase is what produced a 429 on
  /// staging. So: one verify in flight per subscription ([subscriptionKey]), a
  /// transaction verified in this session is never verified again (a redelivery
  /// only retries an import that has not landed), and a subscription the
  /// backend refused for good is answered from memory for the session.
  final Set<String> _inFlight = {};
  final Map<String, String?> _verified = {};
  final Map<String, String> _pendingImports = {};
  final Map<String, IapPurchaseOutcome> _terminal = {};

  /// Transactions whose 200 granted nothing (the subscription had ended, the
  /// account cannot receive access), so a redelivery answers the same.
  final Map<String, IapPurchaseOutcome> _ended = {};

  /// The wait before each verify retry on a 429, a 5xx or a transport failure
  /// (their §2, the guide's §5.5). A `Retry-After` longer than the rung wins.
  /// After the last rung the transaction stays unfinished and the next launch
  /// replays it. Tests inject a shorter ladder.
  final List<Duration> _backoff;

  static const List<Duration> defaultBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 60),
  ];

  /// The longest a `Retry-After` may hold one verify attempt.
  static const _retryAfterCap = Duration(minutes: 5);

  /// Whether a native billing host exists on this platform.
  final bool _supported;

  AuthApiClient get _client => _ref.read(authApiClientProvider);
  SessionTokenStore get _sessionStore => _ref.read(sessionTokenStoreProvider);

  /// Purchase results, pushed as each attempt settles. Broadcast so the notifier
  /// (and the re-verify-on-launch path) can both listen.
  Stream<IapPurchaseOutcome> get outcomes => _outcomes.stream;

  /// Connect to the store. Returns [BillingConnState.unavailable] off-mobile.
  Future<BillingConnState> connect() async =>
      pinConnStateForMarketing(_supported ? await _billing.connect() : BillingConnState.unavailable);

  /// The subscription's offers (base plans + the trial). Empty off-mobile.
  Future<List<RaynOffer>> loadOffers() async =>
      pinOffersForMarketing(_supported ? await _billing.queryOffers(Constants.iapProductId) : const []);

  /// Launch the store's purchase sheet for [offer], binding it to this account
  /// via the stored `user_id` (Play `obfuscatedAccountId`, Apple
  /// `appAccountToken`). The returned [LaunchResult] only says whether the sheet
  /// opened; the purchase itself arrives via the event stream. Null off-mobile.
  Future<LaunchResult?> buy(RaynOffer offer) async {
    // A screenshots build shows plans no store has heard of, so there is no
    // sheet to open. Reported as a cancel rather than a failure so the notifier
    // returns the card to idle instead of painting an error under it: the
    // paywall has to keep looking live while it is being photographed.
    if (isMarketingOffer(offer)) {
      return LaunchResult(responseCode: _BillingResponse.userCanceled, debugMessage: "screenshots build");
    }
    if (!_supported) return null;
    final userId = await _sessionStore.readUserId();
    return _billing.launchPurchase(offer.offerToken, userId ?? '');
  }

  /// Restore Purchases: every subscription the store holds, settled or not,
  /// one verify per subscription. Covers a reinstall and a new device. Returns
  /// whether any purchase was found (each pushes its result on [outcomes]).
  Future<bool> restore() => replay(includeSettled: true);

  /// Re-verify what the store still holds, one transaction per subscription.
  ///
  /// Without [includeSettled] this is the launch replay: only purchases whose
  /// verify never got its answer. With it, Restore: the settled ones too. The
  /// launch replay used to ask for the union, behind a guard that let a settled
  /// entitlement through whenever the account was expired or the profile was
  /// missing — which is how an ended subscription got verified on a fresh
  /// install. The backend already has every settled purchase; the only reason
  /// to send one again is a user asking for a restore.
  Future<bool> replay({required bool includeSettled}) async {
    if (!_supported) return false;
    final purchases = await _billing.queryActivePurchases(includeSettled);
    final newest = newestPerSubscription(purchases.where((p) => p.state == RaynPurchaseState.purchased));
    for (final p in newest) {
      final outcome = await _verifyAndActivate(p);
      if (outcome != null) _outcomes.add(outcome);
    }
    return newest.isNotEmpty;
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
        // One update can carry several transactions of one subscription (a
        // batch of unfinished renewals); one verify covers them all.
        for (final p in newestPerSubscription(purchases)) {
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
        final outcome = await _verifyAndActivate(purchase);
        if (outcome != null) _outcomes.add(outcome);
    }
  }

  /// The subscription API a cryptolink points to returns 404 until the backend's
  /// activation outbox (a ~30s worker) provisions the remnawave user + link, so
  /// we poll the import a few times over ~a minute before giving up.
  static const _activationPollInterval = Duration(seconds: 30);
  static const _maxActivationAttempts = 3; // t = 0s, 30s, 60s.

  /// `POST /iap/{google,apple}/verify`, then wait for provisioning and import
  /// the link.
  ///
  /// `verify` grants + acknowledges and returns the `rayn://` cryptolink, but the
  /// remnawave user + cryptolink are created asynchronously by a ~30s outbox
  /// worker, so the subscription API the link points to 404s until then. We emit
  /// [IapPurchaseOutcome.activating] (drives the "activating your account" screen)
  /// and poll the import until it succeeds ([imported]) or the window elapses
  /// ([stillProvisioning]).
  ///
  /// Null when this delivery duplicated a verify still in flight for the same
  /// subscription: that verify's outcome is the one that counts.
  Future<IapPurchaseOutcome?> _verifyAndActivate(RaynPurchase purchase) async {
    final subscription = subscriptionKey(purchase);
    if (_terminal[subscription] case final refused?) {
      loggy.debug("the backend refused this subscription for good this session; answering from memory");
      return refused;
    }
    if (!_inFlight.add(subscription)) {
      loggy.debug("a verify is already in flight for this subscription; ignoring the duplicate delivery");
      return null;
    }
    try {
      if (_verified.containsKey(purchase.purchaseToken)) return await _settleVerified(purchase);
      return await _verifyOnce(purchase);
    } finally {
      _inFlight.remove(subscription);
    }
  }

  /// A transaction the backend accepted earlier this session. The store keeps
  /// redelivering one only until it is finished, so finish it again
  /// (idempotent), then retry an import that has not landed — the copy asks
  /// the user to tap Restore for exactly that — or report it settled.
  Future<IapPurchaseOutcome> _settleVerified(RaynPurchase purchase) async {
    await _finish(purchase);
    if (_ended[purchase.purchaseToken] case final ended?) return ended;
    final pending = _pendingImports[purchase.purchaseToken];
    if (pending == null) return IapPurchaseOutcome.alreadySettled;
    loggy.info("retrying the import for an already-verified transaction");
    _outcomes.add(IapPurchaseOutcome.activating);
    return _importFor(purchase.purchaseToken, pending);
  }

  /// Runs the import poll and remembers the link until it lands, so a
  /// redelivery retries the import rather than the verify.
  Future<IapPurchaseOutcome> _importFor(String id, String link) async {
    _pendingImports[id] = link;
    final outcome = await _pollImport(link);
    if (outcome == IapPurchaseOutcome.imported) _pendingImports.remove(id);
    return outcome;
  }

  Future<IapPurchaseOutcome> _verifyOnce(RaynPurchase purchase) async {
    final token = await _sessionStore.read();
    if (token == null || token.isEmpty) return IapPurchaseOutcome.needsLogin;

    // One contract, two stores: only the path and the field the purchase id
    // travels under differ. Apple's `transactionId` MUST be a JSON string —
    // `Transaction.id` is a UInt64 and encoding it as a number is a 400.
    final (String path, Map<String, dynamic> body) = switch (_store) {
      IapStore.googlePlay => (
        '/iap/google/verify',
        {'purchaseToken': purchase.purchaseToken, 'productId': purchase.productId},
      ),
      IapStore.appStore => (
        '/iap/apple/verify',
        {'transactionId': purchase.purchaseToken, 'productId': purchase.productId},
      ),
    };

    final Map<String, dynamic> resp;
    try {
      resp = await _postWithBackoff(path, body, token);
    } on AuthApiException catch (e) {
      return _settleRefusal(purchase, e);
    }
    final verdict = VerifyVerdict.parse(resp);

    // 200 means the store answered and the backend applied that answer —
    // access granted, or "this subscription has ended" — and this is the ONLY
    // place the store may be told the purchase was delivered. Finishing any
    // earlier discards a purchase the backend never recorded; while a
    // transaction is unfinished StoreKit keeps redelivering it, which is
    // exactly the retry we want. A deliberate no-op on Play, where the backend
    // acknowledges.
    _verified[purchase.purchaseToken] = switch (verdict) {
      VerifyActive(:final link) || VerifyUnknown(:final link) => link,
      _ => null,
    };
    await _finish(purchase);

    switch (verdict) {
      case VerifyActive(:final link):
        // Their §4: access is back the moment the backend says so. The stored
        // verdict is stale by definition, and waiting for the import to land
        // kept the expired screen up for a purchase Apple had completed.
        await _ref.read(accountStateNotifierProvider.notifier).recordActive();
        return _activate(purchase, link, token);
      case VerifyUnknown(:final link):
        // A backend from before `account_status` shipped, or a link that was
        // not ready in time: the one case where "activating… tap Restore" is
        // the honest thing to say.
        return _activate(purchase, link, token);
      case VerifyEnded(:final storeStatus):
        final outcome = switch (storeStatus) {
          StoreStatus.billingRetry => IapPurchaseOutcome.endedBillingRetry,
          StoreStatus.revoked => IapPurchaseOutcome.endedRevoked,
          StoreStatus.expired || StoreStatus.unknown => IapPurchaseOutcome.ended,
        };
        _ended[purchase.purchaseToken] = outcome;
        loggy.info("verify: the subscription has ended (${storeStatus.name})");
        return outcome;
      case VerifyNotEligible():
        _ended[purchase.purchaseToken] = IapPurchaseOutcome.ineligible;
        loggy.info("verify: nothing granted; the account's email is not verified");
        return IapPurchaseOutcome.ineligible;
      case VerifyPending():
        _ended[purchase.purchaseToken] = IapPurchaseOutcome.accountPending;
        loggy.info("verify: nothing granted; the account is still being activated");
        return IapPurchaseOutcome.accountPending;
      case VerifyUnavailable(:final code):
        _ended[purchase.purchaseToken] = IapPurchaseOutcome.accountUnavailable;
        loggy.warning("verify: the account cannot receive access ($code)");
        // The same signal a poll would bring: the post-auth screens switch to
        // the unavailable mode they already have. Ignored without a profile.
        await _ref.read(accountStateNotifierProvider.notifier).recordFailure(ProfileFailure.accountUnavailable(code));
        return IapPurchaseOutcome.accountUnavailable;
    }
  }

  /// Show the activating screen, then land the link. The fallback fetch
  /// covers a verify that answered before the link was ready.
  Future<IapPurchaseOutcome> _activate(RaynPurchase purchase, String? inline, String token) async {
    _outcomes.add(IapPurchaseOutcome.activating);
    final link = inline ?? await _fetchCryptolink(token);
    if (link == null || link.isEmpty) return IapPurchaseOutcome.stillProvisioning;
    return _importFor(purchase.purchaseToken, link);
  }

  /// Settle [purchase] with the store after the backend has accepted it.
  ///
  /// Failure is not fatal and must not change the outcome: the entitlement is
  /// already applied, and an unfinished transaction is simply redelivered, so
  /// the launch re-verify picks it up. Logs the failure kind only — the
  /// purchase id is a credential.
  Future<void> _finish(RaynPurchase purchase) async {
    if (!_supported) return;
    try {
      await _billing.finishSubscription(purchase.originalId);
    } catch (e) {
      loggy.warning("finishSubscription failed: ${e.runtimeType}");
    }
  }

  /// One verify request, retried on a 429, a 5xx or a transport failure along
  /// [_backoff]. Anything else is the backend's answer and is thrown at once.
  Future<Map<String, dynamic>> _postWithBackoff(String path, Map<String, dynamic> body, String token) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _client.post(path, body, bearer: token);
      } on AuthApiException catch (e) {
        if (!_retryable(e) || attempt >= _backoff.length) rethrow;
        final wait = _waitBefore(e, attempt);
        loggy.info(
          "verify ${e.isUnreachable ? "unreachable" : "answered ${e.status}"}; "
          "retrying in ${wait.inSeconds}s (${attempt + 1}/${_backoff.length})",
        );
        await Future<void>.delayed(wait);
      }
    }
  }

  static bool _retryable(AuthApiException e) => e.isUnreachable || e.status == 429 || e.status >= 500;

  Duration _waitBefore(AuthApiException e, int attempt) {
    final rung = _backoff[attempt];
    final after = e.retryAfter;
    if (after == null || after <= rung) return rung;
    return after > _retryAfterCap ? _retryAfterCap : after;
  }

  /// The backend's final word on a purchase this session. A terminal refusal
  /// (403, 404, 409: another account's purchase, a family-shared one, a
  /// transaction Apple never saw, a token another account already uses) is
  /// finished too, so the store stops redelivering it and re-verifying it at
  /// every launch; Restore still reaches it through the entitlements once the
  /// user has fixed the cause. 401 and the retryable statuses stay unfinished,
  /// which is the retry the guide wants.
  Future<IapPurchaseOutcome> _settleRefusal(RaynPurchase purchase, AuthApiException e) async {
    final outcome = _mapVerifyError(e);
    if (_isTerminal(e)) {
      await _finish(purchase);
      _terminal[subscriptionKey(purchase)] = outcome;
    }
    return outcome;
  }

  static bool _isTerminal(AuthApiException e) => e.status == 403 || e.status == 404 || e.status == 409;

  IapPurchaseOutcome _mapVerifyError(AuthApiException e) {
    if (e.isUnreachable) return IapPurchaseOutcome.unreachable;
    // Status + code only. The verify response carries `Cache-Control: no-store`
    // because it may contain the cryptolink — never log the body.
    loggy.warning("verify rejected: ${e.status} ${e.code}");
    switch (e.code) {
      case 'ACCOUNT_MISMATCH':
        return IapPurchaseOutcome.accountMismatch;
      case 'TOKEN_IN_USE':
        return IapPurchaseOutcome.tokenInUse;
      case 'INELIGIBLE':
        return IapPurchaseOutcome.ineligible;
      case 'FAMILY_SHARED':
        return IapPurchaseOutcome.familyShared;
    }
    if (e.status == 401) return IapPurchaseOutcome.needsLogin;
    if (e.status == 429) return IapPurchaseOutcome.rateLimited;
    // SANDBOX_NOT_ALLOWED, BUNDLE_MISMATCH, 404 TRANSACTION_NOT_FOUND and 404
    // SANDBOX_TRANSACTION_NOT_FOUND are configuration bugs — the wrong backend
    // for this build, or a local .storekit file Apple has never heard of — not
    // user errors. Generic copy, but the log line above carries the code, which
    // is how the backend tells "Apple said no" from "only Sandbox could be
    // asked, and Sandbox said no" (their pre-release mode; after the first App
    // Store release that case is a 500 again and walks the ladder).
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
  ///
  /// A device that already has a profile — a renewal, a plan transition, the
  /// launch re-verify — lands the link on THAT row. A renewed link decrypts to
  /// a different URL whenever the account's state changed, so keying by URL
  /// would add a second profile beside the lapsed one. Only the sign-up
  /// paywall, with no profile yet, adds one.
  Future<IapPurchaseOutcome> _pollImport(String cryptolink) async {
    final RaynLinkOk parsed;
    switch (LinkParser.parse(cryptolink)) {
      case final RaynLinkOk ok:
        parsed = ok;
      case RaynLinkUnsupportedVersion():
        // The purchase is safe; an updated build will import it on Restore.
        return IapPurchaseOutcome.updateRequired;
      case RaynLinkInvalid():
        return IapPurchaseOutcome.failed;
    }

    final repo = await _ref.read(profileRepositoryProvider.future);
    final existing = await _ref.read(activeProfileProvider.future);
    final existingId = existing is RemoteProfileEntity ? existing.id : null;
    for (var attempt = 1; attempt <= _maxActivationAttempts; attempt++) {
      final task = existingId == null
          ? repo.upsertRemote(parsed.url, sourceToken: cryptolink)
          : repo.renewRemote(id: existingId, url: parsed.url, sourceToken: cryptolink);
      final result = await task.run();
      if (result.isRight()) {
        // A config was persisted: whatever verdict was on file, the account is
        // serving again.
        await _ref.read(accountStateNotifierProvider.notifier).recordActive();
        return IapPurchaseOutcome.imported;
      }
      // By reason, never by value. On a release build this is the one line
      // that says which step refused the link when a purchase ends in "tap
      // Restore to finish": the middleware's answer, the local core, or the
      // sealed store.
      final reason = result.fold((failure) => failure.logSummary, (_) => "");
      loggy.warning("activation import attempt $attempt/$_maxActivationAttempts failed: $reason");
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

/// The subscription a purchase belongs to: its original id, or the transaction
/// id when the store gave none (the synthesised pending purchase).
String subscriptionKey(RaynPurchase purchase) =>
    purchase.originalId.isEmpty ? purchase.purchaseToken : purchase.originalId;

/// One purchase per subscription, the newest by purchase date, in first-seen
/// order. The backend fetches the whole subscription's state whichever
/// transaction it is sent, so siblings are duplicates.
List<RaynPurchase> newestPerSubscription(Iterable<RaynPurchase> purchases) {
  final newest = <String, RaynPurchase>{};
  for (final p in purchases) {
    final key = subscriptionKey(p);
    final seen = newest[key];
    if (seen == null || p.purchaseDateMs > seen.purchaseDateMs) newest[key] = p;
  }
  return newest.values.toList();
}
