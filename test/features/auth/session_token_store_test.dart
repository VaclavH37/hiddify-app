import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';

/// In-memory [SessionTokenStore] — overrides every method so the underlying
/// (never-touched) [FlutterSecureStorage] platform channel is never invoked.
class _FakeStore extends SessionTokenStore {
  _FakeStore(this.token) : super(const FlutterSecureStorage());

  String? token;
  bool cleared = false;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async {
    token = null;
    cleared = true;
  }
}

/// In-memory [FlutterSecureStorage] so the REAL [SessionTokenStore] can be
/// exercised end-to-end (no platform channel). Only read/write/delete are used.
class _MemSecureStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('endAuthSession', () {
    test('with a stored token → clears locally', () async {
      final store = _FakeStore('tok-123');

      await endAuthSession(store);

      expect(store.cleared, isTrue);
      expect(store.token, isNull);
    });

    test('with no stored token → still clears', () async {
      final store = _FakeStore(null);

      await endAuthSession(store);

      expect(store.cleared, isTrue);
    });

    test('clears the persisted user_id along with the token (real store)', () async {
      final store = SessionTokenStore(_MemSecureStorage());
      await store.write('tok-123');
      await store.writeUserId('d6b45e25-6cc8-4268-b3af-8f79425f00f7');

      await endAuthSession(store);

      expect(await store.read(), isNull);
      expect(await store.readUserId(), isNull);
    });
  });

  group('SessionTokenStore', () {
    test('round-trips the token and user_id, and clear() removes both', () async {
      final mem = _MemSecureStorage();
      final store = SessionTokenStore(mem);

      await store.write('tok-123');
      await store.writeUserId('d6b45e25-6cc8-4268-b3af-8f79425f00f7');

      expect(await store.read(), 'tok-123');
      expect(await store.readUserId(), 'd6b45e25-6cc8-4268-b3af-8f79425f00f7');

      await store.clear();

      expect(await store.read(), isNull);
      expect(await store.readUserId(), isNull);
      expect(mem.data, isEmpty);
    });
  });
}
