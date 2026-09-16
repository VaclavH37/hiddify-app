import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The renewal screen's sign-in guard: the middleware's account id on the
/// verdict must equal the login's `user_id`, byte for byte (the Worker's
/// final handover, §4.2). An expired login carries no cryptolink, so this is
/// the only ownership check that path has; absent means unknown, not a
/// mismatch.
void main() {
  const uid = '74550193-125b-48ca-9715-f25bb4c8490f';

  /// What an expired account's login returns: a session and its id, no link.
  Map<String, dynamic> expiredLogin({String? userId = uid}) => {
    'session_token': 'sess-abc',
    if (userId != null) 'user_id': userId,
    'account_status': 'expired',
    'status': 'ok',
  };

  Future<(LoginState, _FakeSessionStore)> signIn(Map<String, dynamic> response, {String? expectedAccountId}) async {
    final store = _FakeSessionStore();
    final container = ProviderContainer(
      overrides: [
        authApiClientProvider.overrideWithValue(_FakeAuthApiClient(response)),
        sessionTokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(loginNotifierProvider.notifier)
        .login('me@example.com', 'password12', importProfile: false, expectedAccountId: expectedAccountId);
    return (container.read(loginNotifierProvider), store);
  }

  test('the same id → success, session persisted', () async {
    final (state, store) = await signIn(expiredLogin(), expectedAccountId: uid);
    expect(state.phase, LoginPhase.success);
    expect(store.token, 'sess-abc');
    expect(store.userId, uid);
  });

  test('a different id → accountMismatch, nothing persisted', () async {
    final (state, store) = await signIn(
      expiredLogin(userId: 'ffffffff-0000-4000-8000-000000000000'),
      expectedAccountId: uid,
    );
    expect(state.outcome, LoginOutcome.accountMismatch);
    expect(store.tokenWrites, 0);
    expect(store.userId, isNull);
  });

  test('the comparison is exact: case and whitespace count', () async {
    final (state, _) = await signIn(expiredLogin(userId: uid.toUpperCase()), expectedAccountId: uid);
    expect(state.outcome, LoginOutcome.accountMismatch);
  });

  test('a login without a user_id cannot be confirmed → accountMismatch', () async {
    final (state, store) = await signIn(expiredLogin(userId: null), expectedAccountId: uid);
    expect(state.outcome, LoginOutcome.accountMismatch);
    expect(store.tokenWrites, 0);
  });

  test('no expected id means unknown: any valid account is accepted', () async {
    final (state, store) = await signIn(expiredLogin(userId: 'ffffffff-0000-4000-8000-000000000000'));
    expect(state.phase, LoginPhase.success);
    expect(store.token, 'sess-abc');
  });
}

class _FakeSessionStore extends SessionTokenStore {
  _FakeSessionStore() : super(const FlutterSecureStorage());

  String? token;
  String? userId;
  int tokenWrites = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    token = value;
    tokenWrites++;
  }

  @override
  Future<String?> readUserId() async => userId;

  @override
  Future<void> writeUserId(String value) async => userId = value;

  @override
  Future<void> clear() async {
    token = null;
    userId = null;
  }
}

class _FakeAuthApiClient extends AuthApiClient {
  _FakeAuthApiClient(this.result) : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final Map<String, dynamic> result;

  @override
  Future<Map<String, dynamic>> gatedPost(String path, Map<String, dynamic> body, {String? bearer}) async => result;
}
