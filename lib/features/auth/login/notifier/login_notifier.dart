import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/account_status.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'login_notifier.g.dart';

/// Orchestrates the optional email/password sign-in. Its only job is to acquire
/// the `rayn://import/<token>` subscription URL and feed it into the EXISTING
/// import path ([AddProfileNotifier.addClipboard]); the router's
/// `hasAnyProfileProvider` gate then routes the app to `/home`.
///
/// The 24h `session_token` is persisted to the OS keystore on every successful
/// login ([SessionTokenStore]) so a later Google Play in-app purchase can be
/// associated with the account (e.g. `pending_payment` users who have no
/// subscription to import yet). It is cleared on logout / return-to-auth via
/// [endAuthSession]. The durable *connectivity* state remains the single
/// imported profile — login never gates the tunnel.
@riverpod
class LoginNotifier extends _$LoginNotifier with AppLogger {
  @override
  LoginState build() => LoginState.idle;

  AuthApiClient get _client => ref.read(authApiClientProvider);
  SessionTokenStore get _sessionStore => ref.read(sessionTokenStoreProvider);

  /// [importProfile] is false for the web→Google Play plan-transition re-auth,
  /// which only needs a fresh persisted session (token + user_id) to verify the
  /// purchase — the user already has a profile, so re-running the import would be
  /// rejected by the single-profile guard ("already signed in").
  ///
  /// [expectedSubscriptionUrl] is the active profile's subscription URL. When set
  /// (transition re-auth), the credentials must belong to that same subscription
  /// or the sign-in is rejected with [LoginOutcome.accountMismatch] and **no**
  /// session is persisted — otherwise a different account's credentials would
  /// silently overwrite the session and bind the purchase to the wrong account.
  Future<void> login(
    String email,
    String password, {
    bool importProfile = true,
    String? expectedSubscriptionUrl,
  }) async {
    if (state.isSubmitting) return;
    state = LoginState.submitting;

    try {
      final resp = await _loginWith429Retry(email, password);

      final sessionToken = resp['session_token'] as String?;
      final accountStatus = AccountStatus.fromApi(resp['account_status'] as String?);
      final inlineUrl = resp['subscription_url'] as String?;
      final userId = resp['user_id'] as String?;

      // Plan-transition re-auth: verify the account owns the subscription active
      // on this device BEFORE persisting anything, then store the fresh session
      // and report success without importing (the single-profile guard would
      // reject a re-import). This is the account-switch guard for this path.
      if (!importProfile) {
        if (expectedSubscriptionUrl != null &&
            expectedSubscriptionUrl.isNotEmpty &&
            !_ownsSubscription(inlineUrl, expectedSubscriptionUrl)) {
          state = LoginState.fail(LoginOutcome.accountMismatch);
          return;
        }
        if (sessionToken == null || sessionToken.isEmpty) {
          state = LoginState.fail(LoginOutcome.generic);
          return;
        }
        await _sessionStore.write(sessionToken);
        if (userId != null && userId.isNotEmpty) {
          await _sessionStore.writeUserId(userId);
        }
        state = LoginState.success;
        return;
      }

      // Persist the 24h session token before branching so it's available for a
      // later in-app purchase regardless of which status path we take (notably
      // `pending_payment`, which has no subscription to import). The `user_id`
      // is stored with it — it's the Google Play `obfuscatedAccountId` that
      // binds an in-app purchase to this account (IAP-CLIENT-INTEGRATION.md §3.3).
      if (sessionToken != null && sessionToken.isNotEmpty) {
        await _sessionStore.write(sessionToken);
        if (userId != null && userId.isNotEmpty) {
          await _sessionStore.writeUserId(userId);
        }
      }

      // Happy path: native (PoW) login returns the cryptolink inline — import
      // it directly, no second round-trip.
      if (inlineUrl != null && inlineUrl.isNotEmpty) {
        await _import(inlineUrl);
        return;
      }

      switch (accountStatus) {
        case AccountStatus.active:
          // Token wasn't ready inline; fall back to the subscription endpoint.
          await _fetchAndImport(sessionToken, password);
        case AccountStatus.pendingPayment:
          state = LoginState.fail(LoginOutcome.pendingPayment);
        case AccountStatus.pendingActivation:
          state = LoginState.fail(LoginOutcome.pendingActivation);
        case AccountStatus.expired:
          // Plan lapsed: the session is valid (persisted above) so the user can
          // renew — route to the pricing screen, flagged as the expired variant.
          state = LoginState.fail(LoginOutcome.expired);
        default:
          state = LoginState.fail(LoginOutcome.generic);
      }
    } on AuthApiException catch (e) {
      state = LoginState.fail(_mapError(e));
    } catch (e, st) {
      loggy.warning("unexpected login failure", e, st);
      state = LoginState.fail(LoginOutcome.generic);
    }
  }

  Future<Map<String, dynamic>> _loginWith429Retry(String email, String password) async {
    final body = {'email': email, 'password': password};
    try {
      return await _client.gatedPost('/api/public/login', body);
    } on AuthApiException catch (e) {
      if (e.status != 429) rethrow;
      // Rate limited — back off briefly and retry once.
      await Future<void>.delayed(const Duration(seconds: 2));
      return await _client.gatedPost('/api/public/login', body);
    }
  }

  /// Fallback + refresh path: `GET /account/subscription`, handling the lazy
  /// re-auth window and the "link still being prepared" retry.
  Future<void> _fetchAndImport(String? bearer, String password) async {
    if (bearer == null) {
      state = LoginState.fail(LoginOutcome.generic);
      return;
    }

    var reauthed = false;
    var cryptolinkRetries = 0;
    const maxCryptolinkRetries = 3;

    while (true) {
      try {
        final r = await _client.get('/api/public/account/subscription', bearer: bearer);
        final url = r['subscription_url'] as String?;
        if (url == null || url.isEmpty) {
          state = LoginState.fail(LoginOutcome.generic);
          return;
        }
        await _import(url);
        return;
      } on AuthApiException catch (e) {
        if (e.code == 'REAUTH_REQUIRED' && !reauthed) {
          reauthed = true;
          await _client.gatedPost('/api/public/reauth', {'password': password}, bearer: bearer);
          continue;
        }
        if (e.code == 'CRYPTOLINK_UNAVAILABLE' && cryptolinkRetries < maxCryptolinkRetries) {
          cryptolinkRetries++;
          await Future<void>.delayed(e.retryAfter ?? const Duration(seconds: 5));
          continue;
        }
        if (e.status == 403) {
          // "subscription not available" — account isn't active yet.
          state = LoginState.fail(LoginOutcome.pendingActivation);
          return;
        }
        state = LoginState.fail(_mapError(e));
        return;
      }
    }
  }

  /// Hand the acquired cryptolink to the existing import path. On success the
  /// router redirect (driven by `hasAnyProfileProvider`) replaces this screen
  /// with `/home`.
  Future<void> _import(String subscriptionUrl) async {
    await ref.read(addProfileNotifierProvider.notifier).addClipboard(subscriptionUrl);

    // The session is no longer torn down here — it's persisted (see [login])
    // and cleared later via [endAuthSession] on logout / return-to-auth.

    final importState = ref.read(addProfileNotifierProvider);
    if (importState.hasError) {
      // addClipboard already surfaced its own toast; reflect failure in-form.
      state = LoginState.fail(LoginOutcome.generic);
      return;
    }
    state = LoginState.success;
  }

  /// Whether the account's inline subscription [cryptolink] decrypts to the same
  /// subscription [expectedUrl] active on this device. Used by the transition
  /// re-auth to reject a different account's credentials. A missing/undecryptable
  /// cryptolink (e.g. a `pending_payment` account with no subscription) can't be
  /// confirmed to match, so it fails closed.
  bool _ownsSubscription(String? cryptolink, String expectedUrl) {
    if (cryptolink == null || cryptolink.isEmpty) return false;
    final parsed = LinkParser.parse(cryptolink);
    return parsed != null && parsed.url == expectedUrl;
  }

  LoginOutcome _mapError(AuthApiException e) {
    if (e.isUnreachable) return LoginOutcome.unreachable;
    switch (e.code) {
      case 'EMAIL_NOT_VERIFIED':
        return LoginOutcome.emailNotVerified;
      case 'ACCOUNT_SUSPENDED':
        return LoginOutcome.accountSuspended;
      case 'ACCOUNT_DEACTIVATED':
        return LoginOutcome.accountDeactivated;
    }
    if (e.status == 401) return LoginOutcome.invalidCredentials;
    // 403 with no code is the PoW "challenge verification failed" terminal case
    // (the client already retried once with a fresh challenge).
    if (e.status == 403) return LoginOutcome.verifyFailed;
    return LoginOutcome.generic;
  }
}
