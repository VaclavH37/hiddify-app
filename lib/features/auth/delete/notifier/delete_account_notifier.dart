import 'package:hiddify/features/auth/delete/model/delete_account_state.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/notifier/logout_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'delete_account_notifier.g.dart';

/// Permanently deletes the account via `POST /api/public/account/delete`, then
/// wipes this device.
///
/// App Store guideline 5.1.1(v) requires an app that supports account creation
/// to let the user *initiate* deletion from inside the app, and to delete the
/// account rather than deactivate it.
///
/// Two properties matter and are deliberate:
///
///  * **Bearer + password.** The session alone is not enough authority to
///    destroy an account, so the endpoint re-checks the password. That also
///    makes the request safe to rate-limit aggressively server-side.
///  * **Server first, device second.** The local wipe only runs once the API
///    has confirmed the deletion. Wiping first would strand a user whose
///    request then failed: they would have lost their profile and their token
///    while the account lived on.
///
/// Deleting the account does NOT cancel an App Store or Google Play
/// subscription — only the store can do that. The screen says so before the
/// user confirms; see `t.auth.deleteAccount.consequenceStore`.
@riverpod
class DeleteAccountNotifier extends _$DeleteAccountNotifier with AppLogger {
  @override
  DeleteAccountState build() => DeleteAccountState.idle;

  Future<void> deleteAccount(String password) async {
    if (state.isSubmitting) return;
    state = DeleteAccountState.deleting;

    // Resolved before the request: this notifier is auto-disposed, and the
    // router tears the screen down the moment the profile disappears. Reading
    // providers after that point throws.
    final client = ref.read(authApiClientProvider);
    final logout = ref.read(logoutNotifierProvider.notifier);
    final bearer = await ref.read(sessionTokenStoreProvider).read();

    if (bearer == null) {
      // Token-only user: they authenticated by importing a `rayn://` link and
      // never signed in, so there is no session to authorise a delete. The
      // screen collects credentials and retries.
      state = DeleteAccountState.fail(DeleteAccountOutcome.needsLogin);
      return;
    }

    // No REAUTH_REQUIRED handling: the route re-verifies the password on every
    // call, so session-age gating would add nothing and the backend never
    // returns it here. A bare 403 is a failed proof-of-work, which gatedPost
    // has already retried once with a fresh challenge by the time we see it.
    try {
      await client.gatedPost('/api/public/account/delete', {'password': password}, bearer: bearer);
    } on AuthApiException catch (e) {
      state = DeleteAccountState.fail(_mapError(e));
      return;
    } catch (e, st) {
      loggy.warning("unexpected account-delete failure", e, st);
      state = DeleteAccountState.fail(DeleteAccountOutcome.generic);
      return;
    }

    // The account is gone server-side. That is the terminal truth, so report it
    // before the teardown: the wipe below cannot un-delete anything, and the
    // router disposes this notifier as soon as the profile row goes.
    state = DeleteAccountState.success;

    // Reuses the logout teardown wholesale — clear the session token,
    // disconnect, delete the profile row and its config file. The router's
    // `hasAnyProfileProvider` listener then bounces to /auth.
    await logout.logout();
    loggy.info("account deleted and device wiped");
  }

  /// Maps the account API's contract for this route.
  ///
  /// Every branch here is keyed on the `code` first and the status second,
  /// because on this route the status alone is ambiguous in both directions:
  /// 401 is either a wrong password or a dead session, and 403 is either a
  /// failed proof-of-work or a locked account.
  DeleteAccountOutcome _mapError(AuthApiException e) {
    if (e.isUnreachable) return DeleteAccountOutcome.unreachable;

    // The distinction that matters most. Without it a mistyped password reads
    // as an expired session and throws the user back to the sign-in step.
    if (e.status == 401) {
      return e.code == 'INVALID_CREDENTIALS'
          ? DeleteAccountOutcome.invalidPassword
          : DeleteAccountOutcome.needsLogin;
    }

    // 403 ACCOUNT_LOCKED. Reporting this as a password failure would tell a
    // user under investigation to retype a password that was already correct,
    // forever.
    if (e.code == 'ACCOUNT_LOCKED') return DeleteAccountOutcome.accountLocked;

    if (e.code == 'PAYMENT_IN_FLIGHT') return DeleteAccountOutcome.paymentInFlight;

    // 429 arrives as text/plain with a JSON-shaped body, so it decodes to an
    // empty map and carries no code. The status is the only reliable signal,
    // and there is no Retry-After header anywhere in this API.
    if (e.status == 429) return DeleteAccountOutcome.rateLimited;

    // Includes a bare 403 whose PoW retry also failed, and every 5xx.
    return DeleteAccountOutcome.generic;
  }
}
