import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_preference_group.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class DnsOptionsPage extends HookConsumerWidget {
  const DnsOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final tiles = <Widget>[
      ValuePreferenceWidget(
        value: ref.watch(ConfigOptions.remoteDnsAddress),
        icon: Icons.vpn_lock_rounded,
        preferences: ref.watch(ConfigOptions.remoteDnsAddress.notifier),
        title: t.pages.settings.dns.remoteDns,
      ),
      ChoicePreferenceWidget(
        selected: ref.watch(ConfigOptions.remoteDnsDomainStrategy),
        preferences: ref.watch(ConfigOptions.remoteDnsDomainStrategy.notifier),
        choices: DomainStrategy.values,
        title: t.pages.settings.dns.remoteDnsDomainStrategy,
        icon: Icons.sync_alt_rounded,
        presentChoice: (value) => value.present(t),
      ),
      ValuePreferenceWidget(
        title: t.pages.settings.dns.directDns,
        icon: Icons.public_rounded,
        value: ref.watch(ConfigOptions.directDnsAddress),
        preferences: ref.watch(ConfigOptions.directDnsAddress.notifier),
      ),
      ChoicePreferenceWidget(
        selected: ref.watch(ConfigOptions.directDnsDomainStrategy),
        preferences: ref.watch(ConfigOptions.directDnsDomainStrategy.notifier),
        choices: DomainStrategy.values,
        title: t.pages.settings.dns.directDnsDomainStrategy,
        icon: Icons.sync_alt_rounded,
        presentChoice: (value) => value.present(t),
      ),
    ];

    return RaynPageScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: RaynSpacing.xl),
        children: [
          RaynPageHeader(
            title: t.pages.settings.dns.title,
            subtitle: t.pages.settings.dns.subtitle,
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
