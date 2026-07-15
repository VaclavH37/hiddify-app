import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/disclosure/widget/disclosure_scaffold.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Personal/sensitive-data prominent disclosure (mobile only) — the User Data
/// policy counterpart to [VpnDisclosurePage]. Kept as a SEPARATE screen so the
/// VpnService disclosure stays isolated per Google Play policy. Shown after the
/// VPN disclosure and before `/auth` via the router redirect.
class DataDisclosurePage extends ConsumerWidget {
  const DataDisclosurePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final d = t.disclosure;
    return DisclosureScaffold(
      title: d.data.title,
      sections: [
        DisclosureSection(title: d.data.accountTitle, body: d.data.accountBody),
        DisclosureSection(title: d.data.passwordTitle, body: d.data.passwordBody),
        DisclosureSection(title: d.data.useTitle, body: d.data.useBody),
      ],
      consent: d.data.consent,
      privacyLabel: d.privacyPolicy,
      termsLabel: d.terms,
      agreeLabel: d.agree,
      onAgree: () async {
        await ref.read(Preferences.dataDisclosureAccepted.notifier).update(true);
        // Both disclosures accepted — hand off to the normal gate, which routes
        // to `/auth` (no profile yet) or `/home`.
        if (context.mounted) context.go('/home');
      },
      declineLabel: d.decline,
      onDecline: () => SystemNavigator.pop(),
    );
  }
}
