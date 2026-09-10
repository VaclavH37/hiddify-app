import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/proxy_snapshot_notifier.dart';
import 'package:hiddify/features/proxy/active/selected_location_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
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
            isAutoSelected: display.isAutoSelected,
          );
      // Reflect the pick in the cached snapshot so reopening the list highlights
      // the new choice (not the previously connected node).
      ref.read(proxySnapshotNotifierProvider.notifier).setSelected(proxy.tag);
      if (context.mounted) context.goNamed('home');
    }

    final trailing = <Widget>[
      // Re-runs the URL test for the group. The connection page's latency
      // readout used to be the tap target for this; a readout that is also a
      // button is easy to miss, so it lives here as a named action instead.
      IconButton(
        icon: Icon(Icons.network_check_rounded, color: palette.textPrimary),
        tooltip: t.pages.proxies.testDelay,
        onPressed: isConnected ? () => ref.read(activeProxyNotifierProvider.notifier).urlTest("") : null,
      ),
      PopupMenuButton<ProxiesSort>(
        initialValue: sortBy,
        onSelected: sortNotifier.update,
        icon: Icon(FluentIcons.arrow_sort_24_regular, color: palette.textPrimary),
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
          RaynPageHeader(
            title: t.pages.proxies.title,
            subtitle: t.pages.proxies.subtitle,
            leading: const SubPageBackButton(),
            trailing: trailing,
          ),
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
                final children = <Widget>[];
                for (var i = 0; i < groupItems.length; i++) {
                  if (i > 0) children.add(const SizedBox(height: RaynSpacing.sm));
                  final proxy = groupItems[i];
                  children.add(
                    ProxyTile(
                      proxy,
                      selected: group.selected == proxy.tag,
                      onTap: () async {
                        await handleTap(group.tag, proxy);
                      },
                    ),
                  );
                }
                if (groupItems.isNotEmpty && serverItems.isNotEmpty) {
                  children.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: RaynSpacing.md),
                      child: Divider(color: palette.glassBorder, height: 1, thickness: 1),
                    ),
                  );
                }
                for (var i = 0; i < serverItems.length; i++) {
                  if (i > 0) children.add(const SizedBox(height: RaynSpacing.sm));
                  final proxy = serverItems[i];
                  children.add(
                    ProxyTile(
                      proxy,
                      selected: group.selected == proxy.tag,
                      onTap: () async {
                        await handleTap(group.tag, proxy);
                      },
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, 0, RaynSpacing.xl, RaynSpacing.xl),
                  children: children,
                );
              },
              error: (error, stackTrace) => Center(
                child: Text(t.presentShortError(error), style: TextStyle(color: palette.danger)),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}
