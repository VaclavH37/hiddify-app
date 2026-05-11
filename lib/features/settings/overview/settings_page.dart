import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
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
    // final scrollController = useScrollController();

    // useMemoized(
    //   () {
    //     if (section != null) {
    //       WidgetsBinding.instance.addPostFrameCallback(
    //         (_) {
    //           final box = section!.key.currentContext?.findRenderObject() as RenderBox?;

    //           final offset = box?.localToGlobal(Offset.zero);
    //           if (offset == null) return;
    //           final height = scrollController.offset + offset.dy - MediaQueryData.fromView(View.of(context)).padding.top - kToolbarHeight;
    //           scrollController.animateTo(
    //             height,
    //             duration: const Duration(milliseconds: 500),
    //             curve: Curves.decelerate,
    //           );
    //         },
    //       );
    //     }
    //   },
    // );

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.title)),
      body: ListView(
        children: [
          const AccountSection(),
          const Divider(indent: 16, endIndent: 16),
          SettingsSection(
            title: t.pages.settings.general.title,
            icon: Icons.layers_rounded,
            namedLocation: context.namedLocation('general'),
          ),
          SettingsSection(
            title: t.pages.settings.routing.title,
            icon: Icons.route_rounded,
            namedLocation: context.namedLocation('routeOptions'),
          ),
          SettingsSection(
            title: t.pages.settings.dns.title,
            icon: Icons.dns_rounded,
            namedLocation: context.namedLocation('dnsOptions'),
          ),
          SettingsSection(
            title: t.pages.settings.inbound.title,
            icon: Icons.input_rounded,
            namedLocation: context.namedLocation('inboundOptions'),
          ),
          if (PlatformUtils.isIOS)
            Material(
              child: ListTile(
                title: Text(t.pages.settings.resetTunnel),
                leading: const Icon(Icons.autorenew_rounded),
                onTap: () async {
                  await ref.read(resetTunnelNotifierProvider.notifier).run();
                },
              ),
            ),
          if (Breakpoint(context).isMobile()) ...[
            SettingsSection(
              title: t.pages.logs.title,
              icon: Icons.description_rounded,
              namedLocation: context.namedLocation('logs'),
            ),
            SettingsSection(
              title: t.pages.about.title,
              icon: Icons.info_rounded,
              namedLocation: context.namedLocation('about'),
            ),
          ],
        ],
      ),
    );
  }
}

class SettingsSection extends HookConsumerWidget {
  const SettingsSection({super.key, required this.title, required this.icon, required this.namedLocation});

  final String title;
  final IconData icon;
  final String namedLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.go(namedLocation),
    );
  }
}
