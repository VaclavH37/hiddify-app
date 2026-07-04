import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'session_token_store.g.dart';

/// Securely persists the account API `session_token` — an opaque 24h credential
/// — in the OS keystore (CLIENT-AUTH-INTEGRATION.md §2/§9): Keychain on
/// iOS/macOS, Keystore-backed EncryptedSharedPreferences on Android, DPAPI on
/// Windows, libsecret on Linux. The token is kept after login so a later Google
/// Play in-app purchase can be associated with the user's account. It MUST never
/// be written to `shared_preferences`, Drift, files, or logs.
@Riverpod(keepAlive: true)
SessionTokenStore sessionTokenStore(Ref ref) => const SessionTokenStore(
      FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      ),
    );

class SessionTokenStore {
  const SessionTokenStore(this._storage);

  static const _key = 'rayn_session_token';
  static const _userIdKey = 'rayn_user_id';

  final FlutterSecureStorage _storage;

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  /// The RouteKey account UUID (lowercase canonical form) returned as `user_id`
  /// by `/login` and `/account`. It is passed verbatim to Google Play as the
  /// purchase `obfuscatedAccountId`, which binds an in-app purchase to this
  /// account (IAP-CLIENT-INTEGRATION.md §3.3). Not a secret like the session
  /// token, but stored alongside it so it shares the session lifecycle — both
  /// are written on login and cleared together on logout / return-to-auth.
  Future<String?> readUserId() => _storage.read(key: _userIdKey);

  Future<void> writeUserId(String userId) => _storage.write(key: _userIdKey, value: userId);

  Future<void> clear() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _userIdKey);
  }
}

/// Best-effort server-side session teardown followed by the local clear of the
/// stored token. Shared by the Settings logout and the payment screen's
/// "back to sign in" so both end the API session the same way. The server call
/// is best-effort (the host may be unreachable on a censored network); the
/// local clear always runs.
Future<void> endAuthSession(SessionTokenStore store, AuthApiClient client) async {
  final token = await store.read();
  if (token != null && token.isNotEmpty) {
    try {
      await client.post('/api/public/logout', const {}, bearer: token);
    } catch (_) {
      // Best-effort only — the token still gets cleared locally below.
    }
  }
  await store.clear();
}
