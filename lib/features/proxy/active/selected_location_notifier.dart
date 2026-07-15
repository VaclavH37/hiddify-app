import 'dart:async';
import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'selected_location_notifier.g.dart';

/// The exit location shown on the connection screen: what the user last used, or
/// what they picked pre-connect. Purely a display record — the country code is
/// for the flag, the name is already prettified ("Seoul, SK").
class SelectedLocation {
  const SelectedLocation({
    required this.displayName,
    required this.countryCode,
    required this.isAutoSelected,
  });

  final String displayName;
  final String countryCode;

  /// True for the auto-selector modes (Lowest Latency / Auto rotate) → the tile
  /// subtitle reads "Auto-selected"; false for a specific exit → "Direct".
  final bool isAutoSelected;

  String encode() => jsonEncode({'n': displayName, 'c': countryCode, 'a': isAutoSelected});

  static SelectedLocation? tryDecode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final name = m['n'] as String?;
      if (name == null || name.isEmpty) return null;
      return SelectedLocation(
        displayName: name,
        countryCode: (m['c'] as String?) ?? '',
        isAutoSelected: (m['a'] as bool?) ?? false,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SelectedLocation &&
      other.displayName == displayName &&
      other.countryCode == countryCode &&
      other.isAutoSelected == isAutoSelected;

  @override
  int get hashCode => Object.hash(displayName, countryCode, isAutoSelected);
}

@Riverpod(keepAlive: true)
class SelectedLocationNotifier extends _$SelectedLocationNotifier {
  static const _key = 'selected_location';
  static const _pendingKey = 'selected_location_pending';

  @override
  SelectedLocation? build() {
    // Apply an explicit pre-connect pick once the tunnel comes up. Only fires for
    // a user-made choice (pendingKey set) — otherwise the core reuses its own
    // persisted selection and we must not fight it.
    ref.listen(connectionNotifierProvider, (_, next) {
      if (next.valueOrNull is Connected) unawaited(_applyPending());
    });

    final prefs = ref.watch(sharedPreferencesProvider).requireValue;
    return SelectedLocation.tryDecode(prefs.getString(_key));
  }

  /// Update the displayed location from the live core while connected. Never
  /// marks a pending apply — this only reflects reality.
  Future<void> recordActive(String displayName, String countryCode, bool isAutoSelected) async {
    if (displayName.isEmpty) return;
    final loc = SelectedLocation(displayName: displayName, countryCode: countryCode, isAutoSelected: isAutoSelected);
    if (loc == state) return;
    state = loc;
    await ref.read(sharedPreferencesProvider).requireValue.setString(_key, loc.encode());
  }

  /// Record a pre-connect choice: update the display and queue it to be applied
  /// via `selectOutbound` on the next connect.
  Future<void> choosePreConnect({
    required String groupTag,
    required String outboundTag,
    required String displayName,
    required String countryCode,
    required bool isAutoSelected,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    state = SelectedLocation(displayName: displayName, countryCode: countryCode, isAutoSelected: isAutoSelected);
    await prefs.setString(_key, state!.encode());
    await prefs.setString(_pendingKey, jsonEncode({'g': groupTag, 'o': outboundTag}));
  }

  Future<void> _applyPending() async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final raw = prefs.getString(_pendingKey);
    if (raw == null) return;

    String groupTag = '';
    String outboundTag = '';
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      groupTag = (m['g'] as String?) ?? '';
      outboundTag = (m['o'] as String?) ?? '';
    } catch (_) {}

    if (outboundTag.isEmpty) {
      await prefs.remove(_pendingKey);
      return;
    }

    // Retry across the brief window while the core builds its outbound graph.
    // On persistent failure (e.g. a tag removed by a subscription refresh) give
    // up and leave the core's own default in place.
    final repo = ref.read(proxyRepositoryProvider);
    for (var attempt = 0; attempt < 5; attempt++) {
      final result = await repo.selectProxy(groupTag, outboundTag).run();
      if (result.isRight()) break;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    await prefs.remove(_pendingKey);
  }
}
