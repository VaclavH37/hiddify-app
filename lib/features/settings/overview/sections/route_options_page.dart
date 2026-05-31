import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_preference_group.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RouteOptionsPage extends HookConsumerWidget {
  const RouteOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final tiles = <Widget>[
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
