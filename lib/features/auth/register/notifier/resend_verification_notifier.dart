import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'resend_verification_notifier.g.dart';

enum ResendStatus { idle, sending, sent, failed }

/// Re-sends the verification email via `POST /api/public/resend-verification`
/// (gated/PoW). Dedicated notifier because the verify screen is reached from
/// both registration and the "email not verified" login redirect.
@riverpod
class ResendVerificationNotifier extends _$ResendVerificationNotifier with AppLogger {
  @override
  ResendStatus build() => ResendStatus.idle;

  Future<void> resend(String email) async {
    if (state == ResendStatus.sending) return;
    state = ResendStatus.sending;
    try {
      await ref.read(authApiClientProvider).gatedPost('/api/public/resend-verification', {'email': email});
      // Always 200 regardless of whether the email exists (anti-enumeration).
      state = ResendStatus.sent;
    } on AuthApiException catch (e) {
      loggy.debug("resend-verification failed: status ${e.status}");
      state = ResendStatus.failed;
    } catch (e, st) {
      loggy.warning("unexpected resend-verification failure", e, st);
      state = ResendStatus.failed;
    }
  }
}
