import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_preference_group.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RouteOptionsPage extends HookConsumerWidget {
  const RouteOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final perAppProxy = ref.watch(Preferences.perAppProxyMode).enabled;

    final tiles = <Widget>[
      if (PlatformUtils.isAndroid)
        RaynSettingsTile(
          leading: Icons.apps_rounded,
          title: t.pages.settings.routing.perAppProxy.title,
          trailing: Switch.adaptive(
            value: perAppProxy,
            onChanged: (value) async {
              final newMode = perAppProxy ? PerAppProxyMode.off : PerAppProxyMode.exclude;
              await ref.read(Preferences.perAppProxyMode.notifier).update(newMode);
              if (!perAppProxy && context.mounted) context.goNamed('perAppProxy');
            },
          ),
          onTap: () async {
            if (!perAppProxy) {
              await ref.read(Preferences.perAppProxyMode.notifier).update(PerAppProxyMode.exclude);
            }
            if (context.mounted) context.goNamed('perAppProxy');
          },
        ),
      ChoicePreferenceWidget(
        title: t.pages.settings.routing.balancerStrategy.title,
        icon: Icons.balance_rounded,
        selected: ref.watch(ConfigOptions.balancerStrategy),
        preferences: ref.watch(ConfigOptions.balancerStrategy.notifier),
        choices: BalancerStrategy.values,
        presentChoice: (value) => value.present(t),
      ),
      RaynSwitchTile(
        icon: Icons.block_rounded,
        title: t.pages.settings.routing.blockAds,
        value: ref.watch(ConfigOptions.blockAds),
        onChanged: ref.read(ConfigOptions.blockAds.notifier).update,
      ),
      RaynSwitchTile(
        icon: Icons.call_split_rounded,
        title: t.pages.settings.routing.bypassLan,
        value: ref.watch(ConfigOptions.bypassLan),
        onChanged: ref.read(ConfigOptions.bypassLan.notifier).update,
      ),
      RaynSwitchTile(
        icon: Icons.security_rounded,
        title: t.pages.settings.routing.resolveDestination,
        value: ref.watch(ConfigOptions.resolveDestination),
        onChanged: ref.read(ConfigOptions.resolveDestination.notifier).update,
      ),
      ChoicePreferenceWidget(
        selected: ref.watch(ConfigOptions.ipv6Mode),
        preferences: ref.watch(ConfigOptions.ipv6Mode.notifier),
        choices: IPv6Mode.values,
        title: t.pages.settings.routing.ipv6Route,
        icon: Icons.looks_6_rounded,
        presentChoice: (value) => value.present(t),
      ),
    ];

    return RaynPageScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: RaynSpacing.xl),
        children: [
          RaynPageHeader(
            title: t.pages.settings.routing.title,
            subtitle: t.pages.settings.routing.subtitle,
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
