import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_notice.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/auth/payment/model/purchase_state.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';
import 'package:hiddify/features/auth/payment/widget/iap_outcome_message.dart';
import 'package:hiddify/features/auth/payment/widget/legal_links.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';
import 'package:hiddify/features/auth/payment/widget/purchase_progress.dart';
import 'package:hiddify/features/auth/payment/widget/purchase_unavailable_notice.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
import 'package:hiddify/features/auth/widget/auth_unreachable_help.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/utils/date_time_formatter.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Web → store plan-transition screen. Reached post-auth from Settings →
/// Account (for users whose payment provider isn't store-managed), it converts
/// an active NOWPayments/Guardarian plan to an auto-renewing store subscription
/// — Google Play on Android, the App Store on iOS. The purchase → verify
/// (`/iap/google/verify` or `/iap/apple/verify`, chosen by IapService) →
/// import chain is byte-for-byte identical to the sign-up [PaymentPage];
/// switching ends the current plan immediately and starts a fresh subscription
/// (no remaining-time carry-over) — the client only sees the difference in the
/// response body.
///
/// Verify needs a live account session (24h `session_token` + `user_id`). Most
/// transition users arrive via a token import (no session) or a stale one, and
/// the router blocks `/auth/*` post-auth — so this screen embeds an inline
/// re-auth panel ([_ReauthPanel], reusing [LoginNotifier], which persists a fresh
/// session) instead of navigating away.
class PlanTransitionPage extends HookConsumerWidget {
  const PlanTransitionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;

    final sessionStore = ref.read(sessionTokenStoreProvider);
    // Do we already have a usable session (token + user_id)? Resolved once.
    final sessionSnapshot = useFuture(
      useMemoized(() async {
        final token = await sessionStore.read();
        final userId = await sessionStore.readUserId();
        return (token != null && token.isNotEmpty) && (userId != null && userId.isNotEmpty);
      }),
    );

    // null = still resolving; false = show the sign-in panel; true = show plans.
    final authed = useState<bool?>(null);
    if (authed.value == null && sessionSnapshot.hasData) {
      authed.value = sessionSnapshot.data;
    }

    final state = ref.watch(purchaseNotifierProvider(true));
    final notifier = ref.read(purchaseNotifierProvider(true).notifier);

    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final remote = profile is RemoteProfileEntity ? profile : null;
    final remainingDays = remote?.subInfo != null ? remote!.subInfo!.remaining.inDays : null;

    void close() => context.canPop() ? context.pop() : context.go('/home');

    ref.listen(purchaseNotifierProvider(true), (prev, next) {
      if (prev?.status == next.status && prev?.outcome == next.outcome) return;
      // Imported → refresh the profile (its provider header flips to
      // google_play or app_store, hiding this screen's entry row), confirm, and
      // return to Settings.
      if (next.status == PurchaseStatus.success) {
        ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
        ref.read(inAppNotificationControllerProvider).showSuccessToast(t.auth.planTransition.success);
        close();
        return;
      }
      // Verify can't proceed without a fresh session → drop back to sign-in.
      if (next.status == PurchaseStatus.error &&
          (next.outcome == IapPurchaseOutcome.needsLogin || next.outcome == IapPurchaseOutcome.reauthRequired)) {
        authed.value = false;
      }
    });

    return AuthLayout(
      leading: IconButton(
        icon: Icon(Icons.close_rounded, color: palette.textPrimary),
        tooltip: t.auth.planTransition.close,
        onPressed: close,
      ),
      title: t.auth.planTransition.title,
      children: [
        if (authed.value == null)
          const PurchaseProgress()
        else if (authed.value == false)
          _ReauthPanel(
            t: t,
            // Guard: the credentials must own the subscription active on this
            // device, or re-auth is rejected (no account switch).
            expectedSubscriptionUrl: remote?.url,
            onAuthed: () => authed.value = true,
          )
        else
          ..._plans(t, palette, state, notifier, remainingDays),
      ],
    );
  }

  List<Widget> _plans(
    Translations t,
    RaynPalette palette,
    PurchaseState state,
    PurchaseNotifier notifier,
    int? remainingDays,
  ) {
    switch (state.status) {
      case PurchaseStatus.loading:
        return [PurchaseProgress(label: t.auth.payment.loading)];
      case PurchaseStatus.unavailable:
        return [PurchaseUnavailableNotice(t: t)];
      case PurchaseStatus.success:
        return [PurchaseProgress(label: t.auth.payment.activating)];
      case PurchaseStatus.activating:
        return [PurchaseProgress(label: t.auth.payment.activatingAccount, hint: t.auth.payment.activatingHint)];
      case PurchaseStatus.ready:
      case PurchaseStatus.busy:
      case PurchaseStatus.processing:
      case PurchaseStatus.error:
        final cardsEnabled = state.status == PurchaseStatus.ready || state.status == PurchaseStatus.error;
        return [
          // Transition explainer: shown only when there's trial time to lose, to
          // be transparent that switching ends the current plan and resets the
          // data allowance (no carry-over) before the store takes over
          // auto-renewal.
          if (remainingDays != null && remainingDays > 0) ...[
            RaynNotice(
              icon: Icons.schedule_rounded,
              message: PlatformUtils.isIOS ? t.auth.planTransition.explainerApple : t.auth.planTransition.explainer,
            ),
            const Gap(RaynSpacing.lg),
          ],
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
              footnote: _nextRenewalLabel(t, offer, remainingDays),
            ),
            const Gap(RaynSpacing.md),
          ],
          const Gap(RaynSpacing.sm),
          // Auto-renewal disclosure. This screen completes a real purchase, so
          // guideline 2.3.10 applies exactly as it does on PaymentPage: the
          // wording must not name the other platform. It reads "Google Play" to
          // an iPhone user without this branch.
          Text(
            PlatformUtils.isIOS ? t.auth.payment.autoRenewApple : t.auth.payment.autoRenew,
            style: RaynTypography.caption.copyWith(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          // Terms and Privacy, required by guideline 3.1.2 on the surface where
          // the purchase happens — not only on the sign-up paywall.
          LegalLinks(t: t),
          TextButton(onPressed: state.isBusy ? null : notifier.restore, child: Text(t.auth.payment.restore)),
        ];
    }
  }

  /// Projected first store renewal date shown under each plan: today + the
  /// plan's billing period. The current plan ends immediately on switch (no
  /// remaining-time carry-over), so renewal follows the standard store cycle
  /// from today. A display estimate — the authoritative anchor is set by the
  /// store and the backend.
  String? _nextRenewalLabel(Translations t, RaynOffer offer, int? remainingDays) {
    if (remainingDays == null) return null;
    final next = projectedRenewal(DateTime.now(), offer.billingPeriodIso);
    return t.auth.planTransition.nextBilling(date: next.formatDate());
  }
}

/// Inline email/password sign-in. Reuses [LoginNotifier] (which persists a fresh
/// 24h `session_token` + `user_id` on success) so the transition can proceed
/// without leaving this screen; [onAuthed] fires once a session is in place.
class _ReauthPanel extends HookConsumerWidget {
  const _ReauthPanel({required this.t, required this.onAuthed, this.expectedSubscriptionUrl});

  final Translations t;
  final VoidCallback onAuthed;

  /// The active profile's subscription URL — the credentials must match it.
  final String? expectedSubscriptionUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.rayn;

    final loginState = ref.watch(loginNotifierProvider);
    final isSubmitting = loginState.isSubmitting;

    final emailCtrl = useTextEditingController();
    final passwordCtrl = useTextEditingController();
    final obscure = useState(true);
    final fieldError = useState<String?>(null);

    Future<void> submit() async {
      final email = emailCtrl.text.trim();
      final password = passwordCtrl.text;
      if (email.isEmpty) {
        fieldError.value = t.auth.login.emailEmpty;
        return;
      }
      if (password.isEmpty) {
        fieldError.value = t.auth.login.passwordEmpty;
        return;
      }
      fieldError.value = null;
      // Re-auth only: persist a fresh session for verify — don't re-import the
      // profile (the user already has one; the guard would reject it). The
      // account must own the active subscription, or login reports accountMismatch.
      await ref
          .read(loginNotifierProvider.notifier)
          .login(email, password, importProfile: false, expectedSubscriptionUrl: expectedSubscriptionUrl);
    }

    ref.listen(loginNotifierProvider, (_, next) {
      if (next.phase == LoginPhase.success) onAuthed();
    });

    final errorStyle = RaynTypography.paragraph.copyWith(color: palette.danger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.auth.planTransition.needsSignIn, style: RaynTypography.paragraph.copyWith(color: palette.textSecondary)),
        const Gap(RaynSpacing.lg),
        TextField(
          controller: emailCtrl,
          enabled: !isSubmitting,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: t.auth.login.emailLabel,
            prefixIcon: const Icon(Icons.alternate_email_rounded),
          ),
        ),
        const Gap(RaynSpacing.md),
        TextField(
          controller: passwordCtrl,
          enabled: !isSubmitting,
          obscureText: obscure.value,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            labelText: t.auth.login.passwordLabel,
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(obscure.value ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              onPressed: () => obscure.value = !obscure.value,
            ),
          ),
        ),
        if (fieldError.value != null) ...[const Gap(RaynSpacing.sm), Text(fieldError.value!, style: errorStyle)],
        if (loginState.outcome == LoginOutcome.unreachable) ...[
          const Gap(RaynSpacing.md),
          AuthUnreachableHelp(t: t),
        ] else if (_outcomeMessage(t, loginState.outcome) case final message?) ...[
          const Gap(RaynSpacing.sm),
          Text(message, style: errorStyle),
        ],
        const Gap(RaynSpacing.xl),
        FilledButton(
          onPressed: isSubmitting ? null : submit,
          child: isSubmitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(t.auth.login.signInButton),
        ),
      ],
    );
  }

  /// A transition user's account is active, so most login outcomes shouldn't
  /// occur here — map the ones that can to a message, and fall back to generic.
  String? _outcomeMessage(Translations t, LoginOutcome? outcome) {
    switch (outcome) {
      case null:
      case LoginOutcome.unreachable:
        return null; // unreachable is rendered by AuthUnreachableHelp above.
      case LoginOutcome.invalidCredentials:
        return t.auth.login.invalidCredentials;
      case LoginOutcome.accountMismatch:
        return t.auth.planTransition.accountMismatch;
      case LoginOutcome.accountSuspended:
        return t.auth.login.accountSuspended;
      case LoginOutcome.accountDeactivated:
        return t.auth.login.accountDeactivated;
      case LoginOutcome.emailNotVerified:
        return t.auth.login.emailNotVerified;
      default:
        return t.auth.login.generic;
    }
  }
}
