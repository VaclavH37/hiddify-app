import 'dart:convert';

import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads/writes the [AccountState] JSON blob in SharedPreferences, keyed by the
/// profile it was recorded for so a re-import can never inherit a stale
/// verdict. One key, same shape as `NotificationDedupStore`.
class AccountStateStore {
  AccountStateStore(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'account_state';

  /// The stored verdict for [profileId], or [AccountActive] when there is
  /// none, it belongs to another profile, or it cannot be read.
  AccountState read({required String profileId}) {
    final raw = _prefs.getString(key);
    if (raw == null) return const AccountActive();
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return const AccountActive();
      if (json['profileId'] != profileId) return const AccountActive();
      return AccountState.fromJson(json);
    } catch (_) {
      return const AccountActive();
    }
  }

  Future<void> write({required String profileId, required AccountState state}) async {
    if (state is AccountActive) {
      await clear();
      return;
    }
    await _prefs.setString(key, jsonEncode({'profileId': profileId, ...state.toJson()}));
  }

  Future<void> clear() async {
    await _prefs.remove(key);
  }
}
