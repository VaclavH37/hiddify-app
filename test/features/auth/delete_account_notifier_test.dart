import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/delete/model/delete_account_state.dart';
import 'package:hiddify/features/auth/delete/notifier/delete_account_notifier.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/notifier/logout_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeAuthApiClient extends AuthApiClient {
  _FakeAuthApiClient({this.errors = const {}}) : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  /// path -> error to throw on its FIRST call. Later calls to the same path
  /// succeed, which is what lets the REAUTH_REQUIRED retry be exercised.
  final Map<String, Object> errors;
  final List<String> paths = [];

  @override
  Future<Map<String, dynamic>> gatedPost(String path, Map<String, dynamic> body, {String? bearer}) async {
    final first = !paths.contains(path);
    paths.add(path);
    final err = errors[path];
    if (err != null && first) throw err;
    return const {'status': 'ok'};
  }
}

/// In-memory store, following the same shape as the fake in
/// session_token_store_test.dart: extend and override so the underlying
/// (never-touched) FlutterSecureStorage platform channel is never invoked.
class _FakeSessionStore extends SessionTokenStore {
  _FakeSessionStore(this.token) : super(const FlutterSecureStorage());

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Stands in for the real teardown, which reaches the profile repository and
/// Drift and so needs a Flutter binding and a filesystem. Stubbing it keeps
/// this test on its actual subject — the delete API contract — and lets the
/// "server first, device second" ordering be asserted directly.
class _StubLogoutNotifier extends LogoutNotifier {
  bool called = false;

  @override
  Future<void> logout() async => called = true;
}

void main() {
  late _StubLogoutNotifier stubLogout;

  ProviderContainer containerWith(_FakeAuthApiClient fake, {String? token = 'session-abc'}) {
    stubLogout = _StubLogoutNotifier();
    final c = ProviderContainer(
      overrides: [
        authApiClientProvider.overrideWithValue(fake),
        sessionTokenStoreProvider.overrideWithValue(_FakeSessionStore(token)),
        logoutNotifierProvider.overrideWith(() => stubLogout),
      ],
    );
    addTearDown(c.dispose);
    // Hold a subscription for the life of the test. The notifier is autoDispose,
    // and the success path awaits the logout teardown — long enough for an
    // unlistened provider to be collected and re-created as `idle` on the next
    // read, which would make the assertions below quietly meaningless.
    c.listen(deleteAccountNotifierProvider, (_, _) {}, fireImmediately: true);
    return c;
  }

  test('200 → success, and it hits the delete endpoint', () async {
    final fake = _FakeAuthApiClient();
    final c = containerWith(fake);
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).phase, DeleteAccountPhase.success);
    expect(fake.paths, contains('/api/public/account/delete'));
    expect(stubLogout.called, isTrue, reason: 'the device is wiped once the server confirms');
  });

  test('no stored session → needsLogin, and nothing is sent', () async {
    final fake = _FakeAuthApiClient();
    final c = containerWith(fake, token: null);
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.needsLogin);
    expect(fake.paths, isEmpty, reason: 'must not call delete without a session');
  });

  test('403 INVALID_PASSWORD → invalidPassword', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete': const AuthApiException(status: 403, code: 'INVALID_PASSWORD', message: 'bad password'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('wrong');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.invalidPassword);
  });

  test('REAUTH_REQUIRED → re-auths once and retries the delete', () async {
    final fake = _FakeAuthApiClient(errors: {
      '/api/public/account/delete': const AuthApiException(status: 403, code: 'REAUTH_REQUIRED', message: 'stale session'),
    });
    final c = containerWith(fake);
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).phase, DeleteAccountPhase.success);
    expect(fake.paths, [
      '/api/public/account/delete',
      '/api/public/reauth',
      '/api/public/account/delete',
    ]);
  });

  test('429 → rateLimited', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete': const AuthApiException(status: 429, message: 'slow down'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.rateLimited);
  });

  test('unreachable host → unreachable', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete': AuthApiException.unreachable('no route'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.unreachable);
  });

  test('5xx → generic, and the account is NOT reported deleted', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete': const AuthApiException(status: 500, message: 'boom'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    final s = c.read(deleteAccountNotifierProvider);
    expect(s.outcome, DeleteAccountOutcome.generic);
    expect(s.phase, isNot(DeleteAccountPhase.success));
    expect(stubLogout.called, isFalse,
        reason: 'server first, device second: a failed delete must not wipe the device');
  });
}
