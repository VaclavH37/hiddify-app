import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';

/// Shown when the store's billing host cannot sell to this device — Play
/// Billing missing or disabled, or `AppStore.canMakePayments` false, or the
/// products failing to load at all.
///
/// One widget on purpose. This lived as two near-identical private copies, in
/// payment_page and plan_transition_page, and when the iOS wording was added
/// only one of them was updated — so the upgrade path went on telling iOS users
/// that "Google Play billing isn't available on this device". A shared widget
/// makes that divergence impossible rather than merely unlikely.
///
/// [showAccountLink] offers Android users the account page. It is suppressed on
/// iOS whatever the caller asks for: that page exposes an external way to pay,
/// and linking to one from inside the app is an App Store guideline 3.1.1
/// rejection.
class PurchaseUnavailableNotice extends StatelessWidget {
  const PurchaseUnavailableNotice({super.key, required this.t, this.showAccountLink = false});

  final Translations t;
  final bool showAccountLink;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.auth.payment.unavailableTitle,
          style: RaynTypography.body.copyWith(fontWeight: FontWeight.w600, color: palette.textPrimary),
        ),
        const Gap(RaynSpacing.sm),
        Text(
          PlatformUtils.isIOS ? t.auth.payment.unavailableBodyApple : t.auth.payment.unavailableBody,
          style: RaynTypography.paragraph.copyWith(color: palette.textSecondary),
        ),
        if (showAccountLink && !PlatformUtils.isIOS) ...[
          const Gap(RaynSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(t.auth.payment.openAccount),
            ),
          ),
        ],
      ],
    );
  }
}
