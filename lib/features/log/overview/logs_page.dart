import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class LogsPage extends HookConsumerWidget with PresLogger {
  const LogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final state = ref.watch(logsOverviewNotifierProvider);
    final notifier = ref.watch(logsOverviewNotifierProvider.notifier);

    final debug = ref.watch(debugModeNotifierProvider);
    final pathResolver = ref.watch(logPathResolverProvider);

    final filterController = useTextEditingController(text: state.filter);

    final List<PopupMenuEntry> popupButtons = debug || PlatformUtils.isDesktop
        ? [
            PopupMenuItem(
              child: Text(t.pages.logs.shareCoreLogs),
              onTap: () async {
                await UriUtils.tryShareOrLaunchFile(
                  Uri.parse(pathResolver.coreFile().path),
                  fileOrDir: pathResolver.directory.uri,
                );
              },
            ),
            PopupMenuItem(
              child: Text(t.pages.logs.shareAppLogs),
              onTap: () async {
                await UriUtils.tryShareOrLaunchFile(
                  Uri.parse(pathResolver.appFile().path),
                  fileOrDir: pathResolver.directory.uri,
                );
              },
            ),
          ]
        : [];

    final palette = context.rayn;

    final trailing = <Widget>[
      if (state.paused)
        IconButton(
          onPressed: notifier.resume,
          icon: const Icon(FluentIcons.play_20_regular),
          tooltip: t.common.resume,
          iconSize: 20,
          color: palette.textPrimary,
        )
      else
        IconButton(
          onPressed: notifier.pause,
          icon: const Icon(FluentIcons.pause_20_regular),
          tooltip: t.common.pause,
          iconSize: 20,
          color: palette.textPrimary,
        ),
      IconButton(
        onPressed: notifier.clear,
        icon: const Icon(FluentIcons.delete_lines_20_regular),
        tooltip: t.common.clear,
        iconSize: 20,
        color: palette.textPrimary,
      ),
      if (popupButtons.isNotEmpty)
        PopupMenuButton(
          icon: Icon(AdaptiveIcon(context).more, color: palette.textPrimary),
          itemBuilder: (context) => popupButtons,
        ),
      const RaynNotificationBell(),
    ];

    return RaynPageScaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return <Widget>[
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: MultiSliver(
                children: [
                  SliverToBoxAdapter(
                    child: RaynPageHeader(
                      title: t.pages.logs.title,
                      subtitle: t.pages.logs.subtitle,
                      leading: const SubPageBackButton(),
                      trailing: trailing,
                    ),
                  ),
                  SliverPinnedHeader(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: palette.pageBackground),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, 0, RaynSpacing.xl, RaynSpacing.md),
                        child: GlassSurface(
                          padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.sm),
                          child: Row(
                            children: [
                              Flexible(
                                child: TextFormField(
                                  controller: filterController,
                                  onChanged: notifier.filterMessage,
                                  style: TextStyle(color: palette.textPrimary),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: t.common.filter,
                                    hintStyle: TextStyle(color: palette.textMuted),
                                  ),
                                ),
                              ),
                              const SizedBox(width: RaynSpacing.lg),
                              DropdownButton<Option<LogLevel>>(
                                value: optionOf(state.levelFilter),
                                onChanged: (v) {
                                  if (v == null) return;
                                  notifier.filterLevel(v.toNullable());
                                },
                                padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.sm),
                                borderRadius: BorderRadius.circular(RaynRadius.button),
                                underline: const SizedBox.shrink(),
                                dropdownColor: palette.bgSurface,
                                style: TextStyle(color: palette.textPrimary),
                                items: [
                                  DropdownMenuItem(value: none(), child: Text(t.common.all)),
                                  ...LogLevel.choices.map((e) => DropdownMenuItem(value: some(e), child: Text(e.name))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ];
        },
        body: Builder(
          builder: (context) {
            return CustomScrollView(
              primary: false,
              reverse: true,
              slivers: <Widget>[
                switch (state.logs) {
                  AsyncData(value: final logs) => SliverList.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl, vertical: RaynSpacing.xs),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (log.level != null)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        log.level!.name.toUpperCase(),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium?.copyWith(color: log.level!.color),
                                      ),
                                      if (log.time != null)
                                        Text(
                                          log.time!.toString(),
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall?.copyWith(color: palette.textMuted),
                                        ),
                                    ],
                                  ),
                                Text(
                                  extractMessage(log.message),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.textPrimary),
                                ),
                              ],
                            ),
                          ),
                          if (index != 0)
                            Divider(
                              indent: RaynSpacing.xl,
                              endIndent: RaynSpacing.xl,
                              height: 4,
                              color: palette.glassBorder,
                            ),
                        ],
                      );
                    },
                  ),
                  AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                  _ => const SliverLoadingBodyPlaceholder(),
                },
                SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
              ],
            );
          },
        ),
      ),
    );
  }
}

String extractMessage(String message) {
  final parts = message.split(' ');
  return parts.length <= 2 ? parts.last : parts.sublist(2).join(' ');
}
