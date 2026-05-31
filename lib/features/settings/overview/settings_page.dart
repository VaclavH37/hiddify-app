import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_section_header.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/auth/widget/account_section.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
          _Tile(
            title: t.pages.settings.general.title,
            icon: Icons.layers_rounded,
            location: context.namedLocation('general'),
          ),
          const _SectionDivider(),
          RaynSectionHeader(t.pages.settings.network),
          _Tile(
            title: t.pages.settings.routing.title,
            icon: Icons.route_rounded,
            location: context.namedLocation('routeOptions'),
          ),
          _Tile(
            title: t.pages.settings.dns.title,
            icon: Icons.dns_rounded,
            location: context.namedLocation('dnsOptions'),
          ),
          _Tile(
            title: t.pages.settings.inbound.title,
            icon: Icons.input_rounded,
            location: context.namedLocation('inboundOptions'),
          ),
          if (PlatformUtils.isIOS)
            _Tile(
              title: t.pages.settings.resetTunnel,
              icon: Icons.autorenew_rounded,
              onTap: () async {
                await ref.read(resetTunnelNotifierProvider.notifier).run();
              },
            ),
          if (isMobile) ...[
            const _SectionDivider(),
            RaynSectionHeader(t.pages.about.title),
            _Tile(title: t.pages.logs.title, icon: Icons.description_rounded, location: context.namedLocation('logs')),
            _Tile(title: t.pages.about.title, icon: Icons.info_rounded, location: context.namedLocation('about')),
          ],
        ],
      ),
    );
  }
}

/// Hairline divider between top-level section groups (Account → General →
/// Network → About on mobile). Indented to align with tile content rather
/// than running edge-to-edge.
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
