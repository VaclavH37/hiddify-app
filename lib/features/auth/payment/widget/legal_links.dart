import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/utils/uri_utils.dart';

/// Functional Terms and Privacy links, shown on a purchase surface.
///
/// App Store guideline 3.1.2 requires both to be reachable from the screen
/// where the purchase happens, not only from the store listing. This is shared
/// rather than private to a page because there is more than one such screen —
/// the sign-up paywall and the plan-transition upsell both sell the same
/// subscription, and a copy that lived on only one of them was exactly how the
/// upsell came to ship without either link.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key, required this.t});

  final Translations t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl)),
          child: Text(t.disclosure.terms, style: style),
        ),
        Text('·', style: style),
        TextButton(
          onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl)),
          child: Text(t.disclosure.privacyPolicy, style: style),
        ),
      ],
    );
  }
}
