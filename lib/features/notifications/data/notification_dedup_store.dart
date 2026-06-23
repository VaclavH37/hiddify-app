import 'dart:convert';

import 'package:hiddify/features/notifications/model/notification_dedup_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads/writes the [NotificationDedupState] JSON blob in SharedPreferences.
/// A single key — the state is global (per active profile, tracked inside the
/// blob), not one entry per notification.
class NotificationDedupStore {
  NotificationDedupStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'notifications_dedup_state';

  NotificationDedupState read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return const NotificationDedupState();
    try {
      return NotificationDedupState.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      // Corrupt/legacy blob — start clean rather than crash the monitor.
      return const NotificationDedupState();
    }
  }

  Future<void> write(NotificationDedupState state) async {
    await _prefs.setString(_key, jsonEncode(state.toJson()));
  }
}
