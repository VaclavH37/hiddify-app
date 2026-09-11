import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
import 'package:hiddify/utils/uri_utils.dart';

/// Shared layout for the two mobile prominent-disclosure screens (VpnService +
/// account data): the pre-auth layout with a smaller hero, the titled
/// sections and the consent line in the scroll region, and the affirmative
/// and decline actions pinned beneath it so they are reachable without
/// scrolling. The two screens differ only in their [title] and [sections];
/// consent + policy links + buttons are uniform.
class DisclosureScaffold extends StatelessWidget {
  const DisclosureScaffold({
    super.key,
    required this.title,
    required this.sections,
    required this.consent,
    required this.privacyLabel,
    required this.termsLabel,
    required this.agreeLabel,
    required this.onAgree,
    required this.declineLabel,
    required this.onDecline,
  });

  final String title;
  final List<Widget> sections;
  final String consent;
  final String privacyLabel;
  final String termsLabel;
  final String agreeLabel;
  final VoidCallback onAgree;
  final String declineLabel;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;

    // Back/Home must never count as consent (Play consent policy): the only way
    // forward is the affirmative "Agree & Continue" tap. `canPop: false` makes
    // the system back button an explicit no-op so navigating away is
    // unambiguous — it neither grants consent nor escapes the gate.
    return AuthLayout(
      canPop: false,
      heroWidthFactor: 0.55,
      title: title,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: onAgree, child: Text(agreeLabel)),
          const SizedBox(height: RaynSpacing.xs),
          TextButton(onPressed: onDecline, child: Text(declineLabel)),
        ],
      ),
      children: [
        ...sections,
        Text(consent, style: RaynTypography.caption.copyWith(color: palette.textMuted)),
        const SizedBox(height: RaynSpacing.sm),
        Wrap(
          spacing: RaynSpacing.sm,
          children: [
            TextButton(
              onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl)),
              child: Text(privacyLabel),
            ),
            TextButton(
              onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl)),
              child: Text(termsLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// A titled paragraph within a [DisclosureScaffold] body.
class DisclosureSection extends StatelessWidget {
  const DisclosureSection({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Padding(
      padding: const EdgeInsets.only(bottom: RaynSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: RaynTypography.body.copyWith(fontWeight: FontWeight.w600, color: palette.textPrimary),
          ),
          const SizedBox(height: RaynSpacing.xs),
          Text(body, style: RaynTypography.paragraph.copyWith(color: palette.textSecondary)),
        ],
      ),
    );
  }
}
