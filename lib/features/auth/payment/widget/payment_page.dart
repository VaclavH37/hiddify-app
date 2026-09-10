import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/payment/model/purchase_state.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';
import 'package:hiddify/features/auth/payment/widget/iap_outcome_message.dart';
import 'package:hiddify/features/auth/payment/widget/legal_links.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';
import 'package:hiddify/features/auth/payment/widget/purchase_unavailable_notice.dart';
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
    final theme = Theme.of(context);
    final palette = context.rayn;

    final state = ref.watch(purchaseNotifierProvider(false));
    final notifier = ref.read(purchaseNotifierProvider(false).notifier);

    Future<void> backToSignIn() async {
      // Leaving abandons the pending purchase — tear down the session.
      await endAuthSession(ref.read(sessionTokenStoreProvider));
      if (context.mounted) context.go('/auth');
    }

    return Scaffold(
      backgroundColor: palette.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: t.auth.payment.backToSignIn,
          onPressed: backToSignIn,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Gap(8),
                    const RaynWordmarkHero(),
                    const Gap(32),
                    Text(
                      expired ? t.auth.payment.expiredTitle : t.auth.payment.title,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const Gap(8),
                    if (expired)
                      _ExpiredNotice(message: t.auth.payment.expiredNotice)
                    else
                      Text(
                        t.auth.payment.subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    const Gap(24),
                    ..._content(context, t, theme, palette, state, notifier),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    Translations t,
    ThemeData theme,
    RaynPalette palette,
    PurchaseState state,
    PurchaseNotifier notifier,
  ) {
    switch (state.status) {
      case PurchaseStatus.loading:
        return [_Centered(child: Text(t.auth.payment.loading, style: TextStyle(color: palette.textMuted)))];
      case PurchaseStatus.unavailable:
        return [PurchaseUnavailableNotice(t: t, showAccountLink: true)];
      case PurchaseStatus.success:
        return [_Centered(child: Text(t.auth.payment.activating, style: TextStyle(color: palette.textMuted)))];
      case PurchaseStatus.activating:
        // Dedicated "Activating your account" loading view shown while the
        // backend provisions the subscription (~30s outbox) and we poll.
        return [
          _Centered(
            child: Column(
              children: [
                Text(t.auth.payment.activatingAccount, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                const Gap(6),
                Text(
                  t.auth.payment.activatingHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ];
      case PurchaseStatus.ready:
      case PurchaseStatus.busy:
      case PurchaseStatus.processing:
      case PurchaseStatus.error:
        final cardsEnabled = state.status == PurchaseStatus.ready || state.status == PurchaseStatus.error;
        return [
          if (state.status == PurchaseStatus.processing) ...[
            _Banner(icon: Icons.hourglass_top, message: t.auth.payment.processing, palette: palette),
            const Gap(16),
          ],
          if (state.status == PurchaseStatus.error) ...[
            Text(iapOutcomeMessage(t, state.outcome), style: TextStyle(color: theme.colorScheme.error)),
            const Gap(16),
          ],
          for (final offer in state.offers) ...[
            PlanCard(
              t: t,
              offer: offer,
              busy: state.pendingOfferToken == offer.offerToken,
              enabled: cardsEnabled,
              onTap: () => notifier.buy(offer),
            ),
            const Gap(12),
          ],
          const Gap(8),
          // Auto-renewal disclosure shown next to the purchase action; both stores
          // require it, and Apple's guideline 2.3.10 means the wording must not
          // name the other platform. Price + period are on each card above.
          Text(
            PlatformUtils.isIOS ? t.auth.payment.autoRenewApple : t.auth.payment.autoRenew,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          // Functional Terms and Privacy links, in view before the user buys.
          // App Store guideline 3.1.2 requires both on the purchase surface,
          // not only in the store listing.
          LegalLinks(t: t),
          TextButton(
            onPressed: state.isBusy ? null : notifier.restore,
            child: Text(t.auth.payment.restore),
          ),
        ];
    }
  }
}

/// Centered single-line status (loading / activating) with a spinner.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const Gap(16),
          child,
        ],
      ),
    );
  }
}

/// Info banner (e.g. "payment processing").
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.message, required this.palette});

  final IconData icon;
  final String message;
  final RaynPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.groupFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const Gap(10),
          Expanded(
            child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Warning-tinted banner shown when the user reached this screen because their
/// subscription expired.
class _ExpiredNotice extends StatelessWidget {
  const _ExpiredNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.rayn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: palette.warning, size: 20),
          const Gap(10),
          Expanded(
            child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}
