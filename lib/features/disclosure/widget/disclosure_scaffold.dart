import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/utils/uri_utils.dart';

/// Shared layout for the two mobile prominent-disclosure screens (VpnService +
/// account data). Mirrors the auth/login canvas: brand hero, a scrollable body
/// so the full text is always readable on small screens, a persistent consent
/// line, and pinned affirmative/decline actions. The two screens differ only in
/// their [title] and [sections]; consent + policy links + buttons are uniform.
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
    final theme = Theme.of(context);
    final palette = context.rayn;
    final linkStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );

    // Back/Home must never count as consent (Play consent policy): the only way
    // forward is the affirmative "Agree & Continue" tap. `canPop: false` makes
    // the system back button an explicit no-op so navigating away is
    // unambiguous — it neither grants consent nor escapes the gate.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.bgPrimary,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Gap(8),
                    const RaynWordmarkHero(widthFactor: 0.55),
                    const Gap(24),
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const Gap(16),
                    // Scrollable body: the full disclosure must remain legible on
                    // small screens (and for the review recording).
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...sections,
                            const Gap(8),
                            Text(
                              consent,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                            const Gap(14),
                            Wrap(
                              spacing: 20,
                              runSpacing: 8,
                              children: [
                                GestureDetector(
                                  onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl)),
                                  child: Text(privacyLabel, style: linkStyle),
                                ),
                                GestureDetector(
                                  onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl)),
                                  child: Text(termsLabel, style: linkStyle),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Gap(16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: onAgree,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(
                          agreeLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const Gap(4),
                    TextButton(onPressed: onDecline, child: Text(declineLabel)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const Gap(6),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}
