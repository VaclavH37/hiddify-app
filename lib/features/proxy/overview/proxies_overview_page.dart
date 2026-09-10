import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_section_header.dart';
import 'package:hiddify/core/widget/rayn_settings_group.dart';
import 'package:hiddify/core/widget/sub_page_back_button.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/proxy_snapshot_notifier.dart';
import 'package:hiddify/features/proxy/active/selected_location_notifier.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;

    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final notifier = ref.read(proxiesOverviewNotifierProvider.notifier);
    final sortNotifier = ref.read(proxiesSortNotifierProvider.notifier);
    final isConnected = ref.watch(connectionNotifierProvider.select((v) => v.valueOrNull?.isConnected ?? false));

    // Connected → change the live selection in the core. Disconnected → record
    // the choice against the cached snapshot and return to the home screen; it's
    // applied to the core on the next connect.
    Future<void> handleTap(String groupTag, OutboundInfo proxy) async {
      if (isConnected) {
        await notifier.changeProxy(groupTag, proxy.tag);
        return;
      }
      final display = activeProxyDisplay(proxy, t);
      await ref
          .read(selectedLocationNotifierProvider.notifier)
          .choosePreConnect(
            groupTag: groupTag,
            outboundTag: proxy.tag,
            displayName: display.name,
            countryCode: display.countryCode,
            mode: display.mode,
          );
      // Reflect the pick in the cached snapshot so reopening the list highlights
      // the new choice (not the previously connected node).
      ref.read(proxySnapshotNotifierProvider.notifier).setSelected(proxy.tag);
      if (context.mounted) context.goNamed('home');
    }

    final trailing = <Widget>[
      // Re-runs the latency test. The connection page's latency readout used
      // to be the tap target for this; a readout that is also a button is easy
      // to miss, so it lives here as a named action instead. A plain refresh
      // glyph: the "network check" one read as a wifi dial to nobody.
      IconButton(
        icon: Icon(Icons.refresh_rounded, color: palette.textPrimary),
        tooltip: t.pages.proxies.testDelay,
        onPressed: isConnected ? () => ref.read(activeProxyNotifierProvider.notifier).urlTest("") : null,
      ),
      PopupMenuButton<ProxiesSort>(
        initialValue: sortBy,
        onSelected: sortNotifier.update,
        icon: Icon(Icons.sort_rounded, color: palette.textPrimary),
        tooltip: t.pages.proxies.sort,
        itemBuilder: (context) {
          return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
        },
      ),
      const RaynNotificationBell(),
    ];

    return RaynPageScaffold(
      body: Column(
        children: [
          RaynPageHeader(title: t.pages.proxies.title, leading: const SubPageBackButton(), trailing: trailing),
          Expanded(
            child: proxies.when(
              data: (group) {
                if (group == null || group.items.isEmpty) {
                  // Disconnected with no cache yet (first-ever run) → guide the
                  // user to connect once so the location list can be populated.
                  final message = isConnected ? t.pages.proxies.empty : t.pages.proxies.snapshotEmpty;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.textMuted),
                      ),
                    ),
                  );
                }
                final groupItems = group.items.where((p) => p.isGroup).toList();
                final serverItems = group.items.where((p) => !p.isGroup).toList();
                List<Widget> rows(List<OutboundInfo> items) => [
                  for (final proxy in items)
                    ProxyTile(
                      proxy,
                      selected: group.selected == proxy.tag,
                      onTap: () async {
                        await handleTap(group.tag, proxy);
                      },
                    ),
                ];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, 0, RaynSpacing.xl, RaynSpacing.xl),
                  children: [
                    if (groupItems.isNotEmpty) ...[
                      RaynSectionHeader(t.pages.proxies.automatic),
                      RaynSettingsGroup(children: rows(groupItems)),
                    ],
                    if (serverItems.isNotEmpty) ...[
                      RaynSectionHeader(t.pages.proxies.locations),
                      RaynSettingsGroup(children: rows(serverItems)),
                    ],
                  ],
                );
              },
              error: (error, stackTrace) => Center(
                child: Text(t.presentShortError(error), style: TextStyle(color: palette.danger)),
              ),
              loading: () => const Center(child: CircularProgressIndicator.adaptive()),
            ),
          ),
        ],
      ),
    );
  }
}
