import 'dart:convert';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'proxy_snapshot_notifier.g.dart';

/// One selectable entry in the proxy group, captured while connected so it can
/// be rendered before a core exists (pre-connect location picker).
class SnapshotItem {
  const SnapshotItem({
    required this.tag,
    required this.tagDisplay,
    required this.type,
    required this.isGroup,
    required this.groupSelectedTagDisplay,
    required this.countryCode,
    required this.city,
    required this.region,
    required this.org,
  });

  final String tag;
  final String tagDisplay;
  final String type;
  final bool isGroup;

  /// For an auto-selector group (urltest "Lowest"), the resolved member's tag —
  /// lets the pre-connect display reconstruct "Tokyo, JP" instead of the mode
  /// name. Empty for plain exits / balancer groups.
  final String groupSelectedTagDisplay;

  // Full geo is captured (not just the country) so a balancer's resolved exit
  // renders as "Tokyo, JP" offline, not a bare "JP".
  final String countryCode;
  final String city;
  final String region;
  final String org;

  Map<String, dynamic> toJson() => {
    't': tag,
    'd': tagDisplay,
    'y': type,
    'g': isGroup,
    'sd': groupSelectedTagDisplay,
    'c': countryCode,
    'ci': city,
    'r': region,
    'o': org,
  };

  static SnapshotItem? fromJson(Map<String, dynamic> m) {
    final tag = m['t'] as String?;
    if (tag == null || tag.isEmpty) return null;
    return SnapshotItem(
      tag: tag,
      tagDisplay: (m['d'] as String?) ?? tag,
      type: (m['y'] as String?) ?? '',
      isGroup: (m['g'] as bool?) ?? false,
      groupSelectedTagDisplay: (m['sd'] as String?) ?? '',
      countryCode: (m['c'] as String?) ?? '',
      city: (m['ci'] as String?) ?? '',
      region: (m['r'] as String?) ?? '',
      org: (m['o'] as String?) ?? '',
    );
  }
}

/// A cached copy of the core's top-level outbound group (the "select" group and
/// its members), persisted so the Proxies page can offer a selection before the
/// tunnel — and thus the core — exists.
class ProxySnapshot {
  const ProxySnapshot({required this.groupTag, required this.selectedTag, required this.items});

  final String groupTag;
  final String selectedTag;
  final List<SnapshotItem> items;

  String encode() =>
      jsonEncode({'g': groupTag, 's': selectedTag, 'i': items.map((e) => e.toJson()).toList()});

  static ProxySnapshot? tryDecode(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final items = (m['i'] as List<dynamic>? ?? [])
          .map((e) => SnapshotItem.fromJson(e as Map<String, dynamic>))
          .whereType<SnapshotItem>()
          .toList();
      if (items.isEmpty) return null;
      return ProxySnapshot(
        groupTag: (m['g'] as String?) ?? '',
        selectedTag: (m['s'] as String?) ?? '',
        items: items,
      );
    } catch (_) {
      return null;
    }
  }

  /// Rebuilds a synthetic protobuf [OutboundGroup] so the existing
  /// `ProxiesOverviewPage` (which consumes `OutboundGroup`) can render the cached
  /// list unchanged. Only the fields the page reads are populated; the delay/IP
  /// widgets are already gated on live core data, so their absence is fine.
  OutboundGroup toOutboundGroup() => OutboundGroup(
    tag: groupTag,
    selected: selectedTag,
    items: items.map(
      (it) => OutboundInfo(
        tag: it.tag,
        type: it.type,
        isGroup: it.isGroup,
        tagDisplay: it.tagDisplay,
        groupSelectedTagDisplay: it.groupSelectedTagDisplay,
        ipinfo: IpInfo(countryCode: it.countryCode, city: it.city, region: it.region, org: it.org),
      ),
    ),
  );
}

/// The live top-level outbound group while connected, or null when disconnected.
/// A single always-on subscription (kept alive via [ProxySnapshotNotifier]) so
/// the snapshot is captured just by connecting once — no need to open the list.
@Riverpod(keepAlive: true)
Stream<OutboundGroup?> liveProxyGroup(Ref ref) async* {
  ref.watch(coreRestartSignalProvider);
  final running = ref.watch(serviceRunningProvider);
  if (!running) {
    yield null;
    return;
  }
  yield* ref.watch(proxyRepositoryProvider).watchProxies().map((event) => event.getOrElse((_) => null));
}

@Riverpod(keepAlive: true)
class ProxySnapshotNotifier extends _$ProxySnapshotNotifier {
  static const _key = 'proxy_group_snapshot';
  String? _lastEncoded;

  @override
  ProxySnapshot? build() {
    // Persist every live group emission so the cache tracks subscription changes.
    ref.listen(liveProxyGroupProvider, (_, next) {
      final group = next.valueOrNull;
      if (group != null && group.items.isNotEmpty) _capture(group);
    });

    final prefs = ref.watch(sharedPreferencesProvider).requireValue;
    _lastEncoded = prefs.getString(_key);
    return ProxySnapshot.tryDecode(_lastEncoded);
  }

  void _capture(OutboundGroup group) {
    final snap = ProxySnapshot(
      groupTag: group.tag,
      selectedTag: group.selected,
      items: group.items
          .map(
            (it) => SnapshotItem(
              tag: it.tag,
              tagDisplay: it.tagDisplay,
              type: it.type,
              isGroup: it.isGroup,
              groupSelectedTagDisplay: it.groupSelectedTagDisplay,
              countryCode: it.ipinfo.countryCode,
              city: it.ipinfo.city,
              region: it.ipinfo.region,
              org: it.ipinfo.org,
            ),
          )
          .toList(),
    );
    final encoded = snap.encode();
    if (encoded == _lastEncoded) return;
    _lastEncoded = encoded;
    state = snap;
    ref.read(sharedPreferencesProvider).requireValue.setString(_key, encoded);
  }

  /// Mark [tag] as the selected item in the cached snapshot (after a pre-connect
  /// pick) so the list highlights it the next time it's opened.
  void setSelected(String tag) {
    final current = state;
    if (current == null || current.selectedTag == tag) return;
    final updated = ProxySnapshot(groupTag: current.groupTag, selectedTag: tag, items: current.items);
    final encoded = updated.encode();
    _lastEncoded = encoded;
    state = updated;
    ref.read(sharedPreferencesProvider).requireValue.setString(_key, encoded);
  }
}
