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
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class InboundOptionsPage extends HookConsumerWidget {
  const InboundOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final tiles = <Widget>[
      ChoicePreferenceWidget(
        selected: ref.watch(ConfigOptions.serviceMode),
        preferences: ref.watch(ConfigOptions.serviceMode.notifier),
        choices: ServiceMode.choices,
        title: t.pages.settings.inbound.serviceMode,
        icon: Icons.tune_rounded,
        presentChoice: (value) => value.present(t),
      ),
      RaynSwitchTile(
        icon: Icons.merge_rounded,
        title: t.pages.settings.inbound.strictRoute,
        value: ref.watch(ConfigOptions.strictRoute),
        onChanged: ref.read(ConfigOptions.strictRoute.notifier).update,
      ),
      ChoicePreferenceWidget(
        selected: ref.watch(ConfigOptions.tunImplementation),
        preferences: ref.watch(ConfigOptions.tunImplementation.notifier),
        choices: TunImplementation.values,
        title: t.pages.settings.inbound.tunImplementation,
        icon: Icons.trip_origin_rounded,
        presentChoice: (value) => value.name,
      ),
      ValuePreferenceWidget(
        value: ref.watch(ConfigOptions.mixedPort),
        preferences: ref.watch(ConfigOptions.mixedPort.notifier),
        title: t.pages.settings.inbound.mixedPort,
        icon: Icons.device_hub_rounded,
        inputToValue: int.tryParse,
        digitsOnly: true,
        validateInput: isPort,
      ),
      if (PlatformUtils.isLinux)
        ValuePreferenceWidget(
          value: ref.watch(ConfigOptions.tproxyPort),
          preferences: ref.watch(ConfigOptions.tproxyPort.notifier),
          title: t.pages.settings.inbound.tproxyPort,
          icon: Icons.device_hub_rounded,
          inputToValue: int.tryParse,
          digitsOnly: true,
          validateInput: isPort,
        ),
      if (PlatformUtils.isLinux || PlatformUtils.isMacOS)
        ValuePreferenceWidget(
          value: ref.watch(ConfigOptions.redirectPort),
          preferences: ref.watch(ConfigOptions.redirectPort.notifier),
          title: t.pages.settings.inbound.redirectPort,
          icon: Icons.device_hub_rounded,
          inputToValue: int.tryParse,
          digitsOnly: true,
          validateInput: isPort,
        ),
      ValuePreferenceWidget(
        value: ref.watch(ConfigOptions.directPort),
        preferences: ref.watch(ConfigOptions.directPort.notifier),
        title: t.pages.settings.inbound.directPort,
        icon: Icons.device_hub_rounded,
        inputToValue: int.tryParse,
        digitsOnly: true,
        validateInput: isPort,
      ),
    ];

    return RaynPageScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: RaynSpacing.xl),
        children: [
          RaynPageHeader(
            title: t.pages.settings.inbound.title,
            subtitle: t.pages.settings.inbound.subtitle,
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
