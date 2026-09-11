import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_notice.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/payment/model/purchase_state.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';
import 'package:hiddify/features/auth/payment/widget/iap_outcome_message.dart';
import 'package:hiddify/features/auth/payment/widget/legal_links.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';
import 'package:hiddify/features/auth/payment/widget/purchase_progress.dart';
import 'package:hiddify/features/auth/payment/widget/purchase_unavailable_notice.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Subscription purchase screen, reached after a `pending_payment` (or `expired`)
/// login. It renders the live store offers for the `rayn_premium` subscription
/// and runs the buy → verify → import flow ([PurchaseNotifier]). On success the
/// `rayn://` link is imported and the router redirect (driven by
/// `hasAnyProfileProvider`) swaps this screen for `/home`. The login already
/// persisted the `session_token` + `user_id` so the purchase binds to the account
/// (Play `obfuscatedAccountId`, Apple `appAccountToken`); leaving via the close
/// button tears that session down.
class PaymentPage extends ConsumerWidget {
  const PaymentPage({super.key, this.expired = false});

  /// Whether the user arrived because their plan lapsed (`account_status:
  /// "expired"`) rather than never having paid (`pending_payment`).
  final bool expired;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;

    final state = ref.watch(purchaseNotifierProvider(false));
    final notifier = ref.read(purchaseNotifierProvider(false).notifier);

    Future<void> backToSignIn() async {
      // Leaving abandons the pending purchase — tear down the session.
      await endAuthSession(ref.read(sessionTokenStoreProvider));
      if (context.mounted) context.go('/auth');
    }

    return AuthLayout(
      leading: IconButton(
        icon: Icon(Icons.close_rounded, color: palette.textPrimary),
        tooltip: t.auth.payment.backToSignIn,
        onPressed: backToSignIn,
      ),
      title: expired ? t.auth.payment.expiredTitle : t.auth.payment.title,
      children: [
        if (expired) ...[
          RaynNotice(tone: RaynNoticeTone.warning, message: t.auth.payment.expiredNotice),
          const Gap(RaynSpacing.lg),
        ],
        ..._content(t, palette, state, notifier),
      ],
    );
  }

  List<Widget> _content(Translations t, RaynPalette palette, PurchaseState state, PurchaseNotifier notifier) {
    switch (state.status) {
      case PurchaseStatus.loading:
        return [PurchaseProgress(label: t.auth.payment.loading)];
      case PurchaseStatus.unavailable:
        return [PurchaseUnavailableNotice(t: t, showAccountLink: true)];
      case PurchaseStatus.success:
        return [PurchaseProgress(label: t.auth.payment.activating)];
      case PurchaseStatus.activating:
        // Shown while the backend provisions the subscription (~30s outbox)
        // and we poll.
        return [PurchaseProgress(label: t.auth.payment.activatingAccount, hint: t.auth.payment.activatingHint)];
      case PurchaseStatus.ready:
      case PurchaseStatus.busy:
      case PurchaseStatus.processing:
      case PurchaseStatus.error:
        final cardsEnabled = state.status == PurchaseStatus.ready || state.status == PurchaseStatus.error;
        return [
          if (state.status == PurchaseStatus.processing) ...[
            RaynNotice(icon: Icons.hourglass_top_rounded, message: t.auth.payment.processing),
            const Gap(RaynSpacing.lg),
          ],
          if (state.status == PurchaseStatus.error) ...[
            Text(iapOutcomeMessage(t, state.outcome), style: RaynTypography.paragraph.copyWith(color: palette.danger)),
            const Gap(RaynSpacing.lg),
          ],
          for (final offer in state.offers) ...[
            PlanCard(
              t: t,
              offer: offer,
              busy: state.pendingOfferToken == offer.offerToken,
              enabled: cardsEnabled,
              onTap: () => notifier.buy(offer),
            ),
            const Gap(RaynSpacing.md),
          ],
          const Gap(RaynSpacing.sm),
          // Auto-renewal disclosure shown next to the purchase action; both stores
          // require it, and Apple's guideline 2.3.10 means the wording must not
          // name the other platform. Price + period are on each card above.
          Text(
            PlatformUtils.isIOS ? t.auth.payment.autoRenewApple : t.auth.payment.autoRenew,
            style: RaynTypography.caption.copyWith(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          // Functional Terms and Privacy links, in view before the user buys.
          // App Store guideline 3.1.2 requires both on the purchase surface,
          // not only in the store listing.
          LegalLinks(t: t),
          TextButton(onPressed: state.isBusy ? null : notifier.restore, child: Text(t.auth.payment.restore)),
        ];
    }
  }
}
