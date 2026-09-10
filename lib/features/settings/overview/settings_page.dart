import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_section_header.dart';
import 'package:hiddify/core/widget/rayn_settings_group.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/auth/widget/account_section.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/log/widget/export_diagnostics.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Widest the settings column grows. On a desktop window the rows used to
/// stretch edge to edge, with each switch marooned at the far right; a list
/// of settings is a column of text, and it stays one.
const double _maxContentWidth = 640 + 2 * RaynSpacing.xl;

class SettingsPage extends HookConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isMobile = Breakpoint(context).isMobile();

    final generalTiles = <Widget>[
      const LocalePrefTile(),
      const ThemeModePrefTile(),
      RaynSwitchTile(
        icon: Icons.flag_rounded,
        title: t.pages.settings.general.autoIpCheck,
        value: ref.watch(Preferences.autoCheckIp),
        onChanged: ref.read(Preferences.autoCheckIp.notifier).update,
      ),
      RaynSwitchTile(
        icon: Icons.block_rounded,
        title: t.pages.settings.general.blockAds,
        value: ref.watch(ConfigOptions.blockAds),
        onChanged: ref.read(ConfigOptions.blockAds.notifier).update,
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
    ];

    // Kept in their own group rather than mixed in above. These are for
    // investigating a problem, not for configuring the product: debug mode warns
    // before enabling, and the connection-test URL feeds a hostname the core pins
    // to the CN-direct resolver for 24h, so a bad value there breaks ordinary
    // browsing, not just the probe. Grouping them signals that.
    final advancedTiles = <Widget>[
      RaynSwitchTile(
        icon: Icons.memory_rounded,
        title: t.pages.settings.general.memoryLimit,
        subtitle: t.pages.settings.general.memoryLimitMsg,
        value: !ref.watch(Preferences.disableMemoryLimit),
        onChanged: (value) async => await ref.read(Preferences.disableMemoryLimit.notifier).update(!value),
      ),
      // Debug mode and Log level exist only in a debug build. `kDebugMode` is a
      // const, so in release AOT these two tiles and their string literals are
      // dead-code-eliminated rather than merely hidden.
      //
      // They were removed from shipped builds because they are enumeration tools,
      // not user settings: below `warn` the core logs every connection destination
      // and every DNS lookup, which documents both the user's activity and this
      // client's routing/DNS design. Selecting `debug`/`trace` also sets static.debug
      // in the core, which used to write a goroutine dump naming sing-box and
      // hiddify-core, undoing the de-branding done elsewhere.
      //
      // Nothing is lost in development: a debug build gets both tiles, and
      // bootstrap forces the core's debug flag on regardless.
      if (kDebugMode) ...[
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
      ],
      ValuePreferenceWidget(
        value: ref.watch(ConfigOptions.connectionTestUrl),
        preferences: ref.watch(ConfigOptions.connectionTestUrl.notifier),
        title: t.pages.settings.general.connectionTestUrl,
        icon: Icons.link_rounded,
      ),
      // On iOS this is the ONLY way to read the logs. The tunnel runs in a Network
      // Extension, a separate process the system can start with the app closed, and
      // everything it writes lands in the App Group container, reachable only from a
      // Mac with the device physically attached, which a cloud build host cannot do.
      // There is no in-app log viewer either. Android is no better placed: the working
      // directory is internal storage, so reading it needs adb or root.
      //
      // Without this, the only diagnosis available on device is whatever reaches
      // CoreAlert and shows in the UI, which covers a failed start, but not a tunnel
      // that comes up and then quietly routes nothing.
      if (PlatformUtils.isMobile)
        RaynSettingsTile(
          leading: Icons.share_rounded,
          title: t.pages.settings.exportDiagnostics,
          subtitle: t.pages.settings.exportDiagnosticsMsg,
          onTap: () => exportDiagnostics(context, ref, t),
        ),
      // A recovery action, so it belongs with the other tools for a bad day.
      if (PlatformUtils.isIOS)
        RaynSettingsTile(
          leading: Icons.autorenew_rounded,
          title: t.pages.settings.resetTunnel,
          onTap: () async {
            await ref.read(resetTunnelNotifierProvider.notifier).run();
          },
        ),
    ];

    return RaynPageScaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, 0, RaynSpacing.xl, RaynSpacing.xl),
            children: [
              RaynPageHeader(
                title: t.pages.settings.title,
                padding: const EdgeInsets.only(top: RaynSpacing.xl),
                trailing: const [RaynNotificationBell()],
              ),
              RaynSectionHeader(t.auth.account),
              const AccountSection(),
              RaynSectionHeader(t.pages.settings.general.title),
              RaynSettingsGroup(children: generalTiles),
              RaynSectionHeader(t.pages.settings.advanced),
              RaynSettingsGroup(children: advancedTiles),
              // Desktop and tablet reach About from the navigation rail.
              if (isMobile) ...[
                const SizedBox(height: RaynSpacing.xl),
                RaynSettingsGroup(
                  children: [
                    RaynSettingsTile(
                      leading: Icons.info_outline_rounded,
                      title: t.pages.about.title,
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => context.go(context.namedLocation('about')),
                    ),
                  ],
                ),
              ],
              // Account deletion gets its own group, last on the page. App Store
              // guideline 5.1.1(v) requires it to be reachable in-app; keeping it
              // apart from the Account block means it is never a mis-tap away from
              // Copy token or Restore purchases.
              RaynSectionHeader(t.auth.deleteSection),
              RaynSettingsGroup(
                children: [
                  RaynSettingsTile(
                    leading: Icons.person_remove_outlined,
                    title: t.auth.deleteAccountRow,
                    subtitle: t.auth.deleteAccountRowHint,
                    accentColor: context.rayn.danger,
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.pushNamed('deleteAccount'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
