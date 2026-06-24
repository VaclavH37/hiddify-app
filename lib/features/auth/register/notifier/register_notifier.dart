import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/register/model/register_state.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'register_notifier.g.dart';

/// Creates an account via `POST /api/public/register` using the same gated-POST
/// (PoW) path as login. Registration only *creates* the account
/// (`201 verification_pending`); it returns no token and persists nothing —
/// email verification and payment complete on the website.
@riverpod
class RegisterNotifier extends _$RegisterNotifier with AppLogger {
  @override
  RegisterState build() => RegisterState.idle;

  AuthApiClient get _client => ref.read(authApiClientProvider);

  Future<void> register(String email, String password, String displayName) async {
    if (state.isSubmitting) return;
    state = RegisterState.submitting;

    try {
      await _client.gatedPost('/api/public/register', {
        'email': email,
        'password': password,
        'display_name': displayName,
      });
      // 201 verification_pending — ALSO returned when the email already exists
      // (anti-enumeration). Always advance to the verify screen; never reveal
      // account existence.
      state = RegisterState.success;
    } on AuthApiException catch (e) {
      state = RegisterState.fail(_mapError(e), serverMessage: e.status == 400 ? e.message : null);
    } catch (e, st) {
      loggy.warning("unexpected register failure", e, st);
      state = RegisterState.fail(RegisterOutcome.generic);
    }
  }

  RegisterOutcome _mapError(AuthApiException e) {
    if (e.isUnreachable) return RegisterOutcome.unreachable;
    if (e.status == 400) return RegisterOutcome.validationError;
    // Per-IP cap (3/24h) — an immediate retry won't help, so no auto-retry.
    if (e.status == 429) return RegisterOutcome.tooManyRequests;
    // 403 with no code is the terminal PoW failure (gatedPost already retried once).
    if (e.status == 403) return RegisterOutcome.verifyFailed;
    return RegisterOutcome.generic;
  }
}
