import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
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

    final trailing = <Widget>[
      IconButton(
        onPressed: () async => await notifier.urlTest("select"),
        icon: const Icon(FluentIcons.flash_24_filled),
        tooltip: t.pages.proxies.testDelay,
        iconSize: 20,
        color: palette.textPrimary,
      ),
      PopupMenuButton<ProxiesSort>(
        initialValue: sortBy,
        onSelected: sortNotifier.update,
        icon: Icon(FluentIcons.arrow_sort_24_regular, color: palette.textPrimary),
        tooltip: t.pages.proxies.sort,
        itemBuilder: (context) {
          return [
            ...ProxiesSort.values.map(
              (e) => PopupMenuItem(value: e, child: Text(e.present(t))),
            ),
          ];
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
                  return Center(
                    child: Text(
                      t.pages.proxies.empty,
                      style: TextStyle(color: palette.textMuted),
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
                        await notifier.changeProxy(group.tag, proxy.tag);
                      },
                    ),
                  );
                }
                if (groupItems.isNotEmpty && serverItems.isNotEmpty) {
                  children.add(
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: RaynSpacing.md),
                      child: Divider(
                        color: palette.glassBorder,
                        height: 1,
                        thickness: 1,
                      ),
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
                        await notifier.changeProxy(group.tag, proxy.tag);
                      },
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    RaynSpacing.xl,
                    0,
                    RaynSpacing.xl,
                    RaynSpacing.xl,
                  ),
                  children: children,
                );
              },
              error: (error, stackTrace) => Center(
                child: Text(
                  t.presentShortError(error),
                  style: TextStyle(color: palette.danger),
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}
