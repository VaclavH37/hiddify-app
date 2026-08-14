import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
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
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/auth/widget/account_section.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/log/data/diagnostics_exporter.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

enum ConfigOptionSection {
  fragment;

  static final _fragmentKey = GlobalKey(debugLabel: "fragment-section-key");

  GlobalKey get key => switch (this) {
    ConfigOptionSection.fragment => _fragmentKey,
  };
}

class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isMobile = Breakpoint(context).isMobile();

    // Preferences, formerly the Settings → General sub-page. That page was the last
    // sub-page left once Routing, DNS and Inbound were removed, which left a
    // "General" section header whose only child was a "General" tile — a navigation
    // hop that revealed everything behind it. With this few settings the level of
    // hierarchy earned nothing, so the tiles live here directly.
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

    // Diagnostics, deliberately kept in their own group rather than mixed in above.
    // These are for investigating a problem, not for configuring the product:
    // debug mode warns before enabling, and the connection-test URL feeds a hostname
    // the core pins to the CN-direct resolver for 24h — a bad value there breaks
    // ordinary browsing, not just the probe. Grouping them signals that.
    final troubleshootingTiles = <Widget>[
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
      // hiddify-core — undoing the de-branding done elsewhere.
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
      // everything it writes lands in the App Group container — reachable only from a
      // Mac with the device physically attached, which a cloud build host cannot do.
      // There is no in-app log viewer either. Android is no better placed: the working
      // directory is internal storage, so reading it needs adb or root.
      //
      // Without this, the only diagnosis available on device is whatever reaches
      // CoreAlert and shows in the UI — which covers a failed start, but not a tunnel
      // that comes up and then quietly routes nothing.
      if (PlatformUtils.isMobile)
        RaynSettingsTile(
          leading: Icons.share_rounded,
          title: t.pages.settings.exportDiagnostics,
          subtitle: t.pages.settings.exportDiagnosticsMsg,
          onTap: () async {
            final exporter = DiagnosticsExporter(
              ref.read(appDirectoriesProvider).requireValue.workingDir,
            );
            final files = exporter.collect();
            if (files.isEmpty) {
              if (context.mounted) {
                CustomToast(t.pages.settings.exportDiagnosticsEmpty).show(context);
              }
              return;
            }
            try {
              await Share.shareXFiles([
                for (final file in files) XFile(file.path, mimeType: "text/plain"),
              ]);
            } catch (e) {
              // Fall back to the clipboard rather than dead-ending. The share
              // sheet goes through a native plugin and a UIActivityViewController;
              // when that throws there is nothing to debug from Dart and, on iOS,
              // no second route off the device. Observed failing on a real device.
              //
              // Report by kind, never by value — a platform exception can carry
              // absolute paths, and this is a screen the user may screenshot.
              await Clipboard.setData(ClipboardData(text: exporter.asText()));
              if (context.mounted) {
                CustomToast(t.pages.settings.exportDiagnosticsCopied).show(context);
              }
            }
          },
        ),
      // Was stranded on the settings root under no header at all, left behind when
      // the Network section was removed. It is a recovery action, so it belongs here.
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
      body: ListView(
        padding: const EdgeInsets.only(bottom: RaynSpacing.xl),
        children: [
          RaynPageHeader(
            title: t.pages.settings.title,
            subtitle: t.pages.settings.subtitle,
            trailing: const [RaynNotificationBell()],
          ),
          RaynSectionHeader(t.auth.account),
          const AccountSection(),
          const _SectionDivider(),
          RaynSectionHeader(t.pages.settings.general.title),
          _TileColumn(children: generalTiles),
          const _SectionDivider(),
          RaynSectionHeader(t.pages.settings.troubleshooting),
          _TileColumn(children: troubleshootingTiles),
          if (isMobile) ...[
            const _SectionDivider(),
            RaynSectionHeader(t.pages.about.title),
            _Tile(title: t.pages.about.title, icon: Icons.info_rounded, location: context.namedLocation('about')),
          ],
        ],
      ),
    );
  }
}

/// A section's tiles, stacked and inset to line up with the section headers.
///
/// Deliberately plain: no `RaynPreferenceGroup` wrapper. These tiles used to live
/// on sub-pages, where a filled, bordered, hairline-separated container set them
/// apart from the page around them. Inlined onto the settings root that container
/// read as a foreign element — the Account block above and the About row below are
/// bare [RaynSettingsTile]s on the page background, so General and Troubleshooting
/// were the only boxed sections on the screen.
///
/// Matches [AccountSection]'s layout exactly (same padding, same bare Column) so
/// every section on this page shares one treatment.
class _TileColumn extends StatelessWidget {
  const _TileColumn({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
      child: Column(children: children),
    );
  }
}

/// Hairline divider between top-level section groups (Account → General →
/// Troubleshooting → About on mobile). Indented to align with tile content
/// rather than running edge-to-edge.
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.md, RaynSpacing.xl, 0),
      child: Divider(height: 1, thickness: 1, color: context.rayn.glassBorder),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.icon, this.location, this.onTap})
    : assert(location != null || onTap != null);

  final String title;
  final IconData icon;
  final String? location;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
      child: RaynSettingsTile(
        leading: icon,
        title: title,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap ?? () => context.go(location!),
      ),
    );
  }
}
