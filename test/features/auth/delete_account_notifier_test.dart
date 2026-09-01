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

  // Both 401 shapes exist on this route and mean opposite things. Getting these
  // two the wrong way round sends a user who mistyped their password back to
  // the sign-in screen, which is what the first implementation did.
  test('401 INVALID_CREDENTIALS → invalidPassword, and stays on this screen', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete':
          const AuthApiException(status: 401, code: 'INVALID_CREDENTIALS', message: 'invalid credentials'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('wrong');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.invalidPassword);
  });

  test('bare 401 → needsLogin', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete': const AuthApiException(status: 401, message: 'unauthorized'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.needsLogin);
  });

  test('403 ACCOUNT_LOCKED → accountLocked, never a password error', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete':
          const AuthApiException(status: 403, code: 'ACCOUNT_LOCKED', message: 'under investigation'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.accountLocked,
        reason: 'a locked account retyping a correct password must not be told it is wrong');
  });

  test('409 PAYMENT_IN_FLIGHT → paymentInFlight', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete':
          const AuthApiException(status: 409, code: 'PAYMENT_IN_FLIGHT', message: 'payment settling'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.paymentInFlight);
  });

  // gatedPost retries a bare 403 once with a fresh challenge. If it still fails
  // the proof-of-work is genuinely not being accepted, which is not something
  // the user can fix by retyping anything.
  test('bare 403 that survived the PoW retry → generic', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete': const AuthApiException(status: 403, message: 'forbidden'),
    }));
    await c.read(deleteAccountNotifierProvider.notifier).deleteAccount('hunter2hunter2');
    expect(c.read(deleteAccountNotifierProvider).outcome, DeleteAccountOutcome.generic);
  });

  // A 429 body is text/plain despite looking like JSON, so it decodes to an
  // empty map and carries no code — the status is all there is to branch on.
  test('429 with no code → rateLimited', () async {
    final c = containerWith(_FakeAuthApiClient(errors: {
      '/api/public/account/delete': const AuthApiException(status: 429, message: 'too many requests'),
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
