import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/register/notifier/resend_verification_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeAuthApiClient extends AuthApiClient {
  _FakeAuthApiClient({this.error}) : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final Object? error;

  @override
  Future<Map<String, dynamic>> gatedPost(String path, Map<String, dynamic> body, {String? bearer}) async {
    if (error != null) throw error!;
    return const {};
  }
}

void main() {
  test('success → sent (200 regardless of existence)', () async {
    final c = ProviderContainer(overrides: [authApiClientProvider.overrideWithValue(_FakeAuthApiClient())]);
    addTearDown(c.dispose);
    await c.read(resendVerificationNotifierProvider.notifier).resend('user@example.com');
    expect(c.read(resendVerificationNotifierProvider), ResendStatus.sent);
  });

  test('error → failed (kept neutral)', () async {
    final c = ProviderContainer(
      overrides: [
        authApiClientProvider.overrideWithValue(_FakeAuthApiClient(error: const AuthApiException(status: 429, message: 'x'))),
      ],
    );
    addTearDown(c.dispose);
    await c.read(resendVerificationNotifierProvider.notifier).resend('user@example.com');
    expect(c.read(resendVerificationNotifierProvider), ResendStatus.failed);
  });
}
