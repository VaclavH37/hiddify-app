import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/disclosure/widget/disclosure_scaffold.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Standalone Google Play VpnService prominent disclosure (mobile only). Per
/// policy this MUST be a separate disclosure — it explains only why the app
/// uses the VPN service and how the traffic it handles is used, with no
/// personal/sensitive-data disclosures mixed in (that is the sibling
/// [DataDisclosurePage]). Shown before `/auth` via the router redirect.
class VpnDisclosurePage extends ConsumerWidget {
  const VpnDisclosurePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final d = t.disclosure;
    return DisclosureScaffold(
      title: d.vpn.title,
      sections: [
        DisclosureSection(title: d.vpn.whyTitle, body: d.vpn.whyBody),
        DisclosureSection(title: d.vpn.dataTitle, body: d.vpn.dataBody),
        DisclosureSection(title: d.vpn.trafficTitle, body: d.vpn.trafficBody),
      ],
      consent: d.vpn.consent,
      privacyLabel: d.privacyPolicy,
      termsLabel: d.terms,
      agreeLabel: d.agree,
      onAgree: () async {
        await ref.read(Preferences.vpnDisclosureAccepted.notifier).update(true);
        // Advance to the second, separate disclosure; the redirect keeps us
        // there until it too is accepted.
        if (context.mounted) context.go('/disclosure/data');
      },
      declineLabel: d.decline,
      onDecline: () => SystemNavigator.pop(),
    );
  }
}
