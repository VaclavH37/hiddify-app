import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/register/model/register_state.dart';
import 'package:hiddify/features/auth/register/notifier/register_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeAuthApiClient extends AuthApiClient {
  _FakeAuthApiClient({this.result, this.error}) : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final Map<String, dynamic>? result;
  final Object? error;
  final List<String> paths = [];

  @override
  Future<Map<String, dynamic>> gatedPost(String path, Map<String, dynamic> body, {String? bearer}) async {
    paths.add(path);
    if (error != null) throw error!;
    return result ?? const {};
  }
}

void main() {
  ProviderContainer containerWith(_FakeAuthApiClient fake) {
    final c = ProviderContainer(overrides: [authApiClientProvider.overrideWithValue(fake)]);
    addTearDown(c.dispose);
    return c;
  }

  test('201 → success and hits the register endpoint', () async {
    final fake = _FakeAuthApiClient(result: const {'status': 'verification_pending'});
    final c = containerWith(fake);
    await c.read(registerNotifierProvider.notifier).register('user@example.com', 'a' * 10, 'Alex');
    expect(c.read(registerNotifierProvider).phase, RegisterPhase.success);
    expect(fake.paths, ['/api/public/register']);
  });

  test('400 → validationError carrying the server message', () async {
    final c = containerWith(_FakeAuthApiClient(error: const AuthApiException(status: 400, message: 'password is too common')));
    await c.read(registerNotifierProvider.notifier).register('user@example.com', 'password12', 'Alex');
    final s = c.read(registerNotifierProvider);
    expect(s.outcome, RegisterOutcome.validationError);
    expect(s.serverMessage, 'password is too common');
  });

  test('429 → tooManyRequests', () async {
    final c = containerWith(_FakeAuthApiClient(error: const AuthApiException(status: 429, message: 'too many requests')));
    await c.read(registerNotifierProvider.notifier).register('user@example.com', 'password12', 'Alex');
    expect(c.read(registerNotifierProvider).outcome, RegisterOutcome.tooManyRequests);
  });

  test('403 → verifyFailed', () async {
    final c = containerWith(_FakeAuthApiClient(error: const AuthApiException(status: 403, message: 'challenge verification failed')));
    await c.read(registerNotifierProvider.notifier).register('user@example.com', 'password12', 'Alex');
    expect(c.read(registerNotifierProvider).outcome, RegisterOutcome.verifyFailed);
  });

  test('unreachable host → unreachable', () async {
    final c = containerWith(_FakeAuthApiClient(error: AuthApiException.unreachable('no route')));
    await c.read(registerNotifierProvider.notifier).register('user@example.com', 'password12', 'Alex');
    expect(c.read(registerNotifierProvider).outcome, RegisterOutcome.unreachable);
  });
}
