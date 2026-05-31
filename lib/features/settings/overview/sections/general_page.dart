import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_preference_group.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:humanizer/humanizer.dart';

class GeneralPage extends HookConsumerWidget {
  const GeneralPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final tiles = <Widget>[
      const LocalePrefTile(),
      const ThemeModePrefTile(),
      const EnableAnalyticsPrefTile(),
      RaynSwitchTile(
        icon: Icons.flag_rounded,
        title: t.pages.settings.general.autoIpCheck,
        value: ref.watch(Preferences.autoCheckIp),
        onChanged: ref.read(Preferences.autoCheckIp.notifier).update,
      ),
      if (PlatformUtils.isAndroid) ...[
        RaynSwitchTile(
          icon: Icons.speed_rounded,
          title: t.pages.settings.general.dynamicNotification,
          value: ref.watch(Preferences.dynamicNotification),
          onChanged: ref.read(Preferences.dynamicNotification.notifier).update,
        ),
        RaynSwitchTile(
          icon: Icons.vibration_rounded,
          title: t.pages.settings.general.hapticFeedback,
          value: ref.watch(hapticServiceProvider),
          onChanged: ref.read(hapticServiceProvider.notifier).updatePreference,
        ),
      ],
      if (PlatformUtils.isDesktop) ...[
        const ClosingPrefTile(),
        RaynSwitchTile(
          icon: Icons.auto_mode_rounded,
          title: t.pages.settings.general.autoStart,
          value: ref.watch(autoStartNotifierProvider).asData?.value ?? false,
          onChanged: (value) async => value
              ? await ref.read(autoStartNotifierProvider.notifier).enable()
              : await ref.read(autoStartNotifierProvider.notifier).disable(),
        ),
        RaynSwitchTile(
          icon: Icons.visibility_off_rounded,
          title: t.pages.settings.general.silentStart,
          value: ref.watch(Preferences.silentStart),
          onChanged: ref.read(Preferences.silentStart.notifier).update,
        ),
      ],
      if (PlatformUtils.isAndroid) const BatteryOptimizationWidget(),
      RaynSwitchTile(
        icon: Icons.memory_rounded,
        title: t.pages.settings.general.memoryLimit,
        subtitle: t.pages.settings.general.memoryLimitMsg,
        value: !ref.watch(Preferences.disableMemoryLimit),
        onChanged: (value) async => await ref.read(Preferences.disableMemoryLimit.notifier).update(!value),
      ),
      RaynSwitchTile(
        icon: Icons.bug_report_rounded,
        title: t.pages.settings.general.debugMode,
        value: ref.watch(debugModeNotifierProvider),
        onChanged: (value) async {
          if (value) {
            await ref
                .read(dialogNotifierProvider.notifier)
                .showOk(t.pages.settings.general.debugMode, t.pages.settings.general.debugModeMsg);
          }
          await ref.read(debugModeNotifierProvider.notifier).update(value);
        },
      ),
      ChoicePreferenceWidget(
        selected: ref.watch(ConfigOptions.logLevel),
        preferences: ref.watch(ConfigOptions.logLevel.notifier),
        choices: LogLevel.choices,
        title: t.pages.settings.general.logLevel,
        icon: Icons.description_rounded,
        presentChoice: (value) => value.name.toUpperCase(),
      ),
      ValuePreferenceWidget(
        value: ref.watch(ConfigOptions.connectionTestUrl),
        preferences: ref.watch(ConfigOptions.connectionTestUrl.notifier),
        title: t.pages.settings.general.connectionTestUrl,
        icon: Icons.link_rounded,
      ),
      _UrlTestIntervalTile(),
    ];

    return RaynPageScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: RaynSpacing.xl),
        children: [
          RaynPageHeader(
            title: t.pages.settings.general.title,
            subtitle: t.pages.settings.general.subtitle,
            leading: const SubPageBackButton(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
            child: RaynPreferenceGroup(children: tiles),
          ),
        ],
      ),
    );
  }
}

class _UrlTestIntervalTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final interval = ref.watch(ConfigOptions.urlTestInterval);
    final palette = context.rayn;
    return RaynSettingsTile(
      leading: Icons.timer_rounded,
      title: t.pages.settings.general.urlTestInterval,
      trailing: Text(
        interval.toApproximateTime(isRelativeToNow: false),
        style: RaynTypography.body.copyWith(color: palette.textMuted),
      ),
      onTap: () async => await ref
          .read(dialogNotifierProvider.notifier)
          .showSettingSlider(
            title: t.pages.settings.general.urlTestInterval,
            initialValue: interval.inMinutes.coerceIn(0, 60).toDouble(),
            onReset: ref.read(ConfigOptions.urlTestInterval.notifier).reset,
            min: 1,
            max: 60,
            divisions: 60,
            labelGen: (value) => Duration(minutes: value.toInt()).toApproximateTime(isRelativeToNow: false),
          )
          .then((value) async {
            if (value == null) return;
            await ref.read(ConfigOptions.urlTestInterval.notifier).update(Duration(minutes: value.toInt()));
          }),
    );
  }
}
