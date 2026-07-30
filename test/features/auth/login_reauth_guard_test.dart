import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/rayn_link_fixture.dart';

/// Records what the session store is asked to persist so a test can assert that
/// a mismatched account's credentials never overwrite the session.
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

/// A login response whose inline `subscription_url` cryptolink decrypts to [url].
Map<String, dynamic> _loginResponse(String url, {int version = kLinkVersionV2}) => {
      'session_token': 'sess-abc',
      'user_id': 'uid-123',
      'account_status': 'active',
      'subscription_url': mintRaynLink(url, version: version),
    };

void main() {
  setUp(useTestSecret);
  tearDown(useEmbeddedKey);

  const activeUrl = 'https://subscription-api.example.com/AccountA?x=1';

  ProviderContainer containerWith(_FakeAuthApiClient api, _FakeSessionStore store) {
    final c = ProviderContainer(
      overrides: [
        authApiClientProvider.overrideWithValue(api),
        sessionTokenStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('plan-transition re-auth guard (importProfile: false)', () {
    test('same account → success and persists the fresh session', () async {
      final store = _FakeSessionStore();
      final c = containerWith(_FakeAuthApiClient(_loginResponse(activeUrl)), store);

      await c.read(loginNotifierProvider.notifier).login(
            'me@example.com',
            'password12',
            importProfile: false,
            expectedSubscriptionUrl: activeUrl,
          );

      expect(c.read(loginNotifierProvider).phase, LoginPhase.success);
      expect(store.token, 'sess-abc');
      expect(store.userId, 'uid-123');
    });

    test('different account → accountMismatch and NO session is persisted', () async {
      final store = _FakeSessionStore();
      // The credentials authenticate to a different subscription than the active one.
      final c = containerWith(_FakeAuthApiClient(_loginResponse('https://subscription-api.example.com/AccountB')), store);

      await c.read(loginNotifierProvider.notifier).login(
            'other@example.com',
            'password12',
            importProfile: false,
            expectedSubscriptionUrl: activeUrl,
          );

      final s = c.read(loginNotifierProvider);
      expect(s.phase, LoginPhase.outcome);
      expect(s.outcome, LoginOutcome.accountMismatch);
      // The security property: a foreign account's session must never be stored.
      expect(store.tokenWrites, 0);
      expect(store.token, isNull);
      expect(store.userId, isNull);
    });

    test('undecryptable subscription link fails closed (accountMismatch)', () async {
      final store = _FakeSessionStore();
      final c = containerWith(
        _FakeAuthApiClient(const {
          'session_token': 'sess-abc',
          'user_id': 'uid-123',
          'account_status': 'active',
          'subscription_url': 'rayn://import/not-a-real-token',
        }),
        store,
      );

      await c.read(loginNotifierProvider.notifier).login(
            'me@example.com',
            'password12',
            importProfile: false,
            expectedSubscriptionUrl: activeUrl,
          );

      expect(c.read(loginNotifierProvider).outcome, LoginOutcome.accountMismatch);
      expect(store.tokenWrites, 0);
    });

    test('an unreadable envelope version also fails closed (accountMismatch)', () async {
      // We can't confirm ownership of a link we can't open, and this guard's
      // contract is "reject what we can't verify" — the user learns an update is
      // needed from the import path, not by having a foreign session persisted.
      final store = _FakeSessionStore();
      final c = containerWith(_FakeAuthApiClient(_loginResponse(activeUrl, version: 0x03)), store);

      await c.read(loginNotifierProvider.notifier).login(
            'me@example.com',
            'password12',
            importProfile: false,
            expectedSubscriptionUrl: activeUrl,
          );

      expect(c.read(loginNotifierProvider).outcome, LoginOutcome.accountMismatch);
      expect(store.tokenWrites, 0);
    });

    test('no expected account (guard disabled) → success and persists', () async {
      final store = _FakeSessionStore();
      final c = containerWith(_FakeAuthApiClient(_loginResponse(activeUrl)), store);

      await c.read(loginNotifierProvider.notifier).login('me@example.com', 'password12', importProfile: false);

      expect(c.read(loginNotifierProvider).phase, LoginPhase.success);
      expect(store.token, 'sess-abc');
    });
  });
}
