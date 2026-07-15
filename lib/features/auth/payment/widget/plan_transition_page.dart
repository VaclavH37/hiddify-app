import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/auth/payment/model/purchase_state.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';
import 'package:hiddify/features/auth/widget/auth_unreachable_help.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/utils/date_time_formatter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Web → Google Play plan-transition screen. Reached post-auth from
/// Settings → Account (for users whose payment provider isn't `google_play`), it
/// converts an active NOWPayments/Guardarian plan to an auto-renewing Google Play
/// subscription. The purchase → `POST /iap/google/verify` → import chain is
/// byte-for-byte identical to the sign-up [PaymentPage]; the backend branches on
/// the user's status (deferring the next billing anchor by their remaining paid
/// time) and the client only sees the difference in the response body.
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
    final theme = Theme.of(context);
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
      // Imported → refresh the profile (its provider header flips to google_play,
      // hiding this screen's entry row), confirm, and return to Settings.
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

    return Scaffold(
      backgroundColor: palette.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: t.auth.planTransition.close,
          onPressed: close,
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
                      t.auth.planTransition.title,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const Gap(16),
                    if (authed.value == null)
                      const _CenteredSpinner()
                    else if (authed.value == false)
                      _ReauthPanel(
                        t: t,
                        // Guard: the credentials must own the subscription active
                        // on this device, or re-auth is rejected (no account switch).
                        expectedSubscriptionUrl: remote?.url,
                        onAuthed: () => authed.value = true,
                      )
                    else
                      ..._plans(context, t, theme, palette, state, notifier, remainingDays),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _plans(
    BuildContext context,
    Translations t,
    ThemeData theme,
    RaynPalette palette,
    PurchaseState state,
    PurchaseNotifier notifier,
    int? remainingDays,
  ) {
    switch (state.status) {
      case PurchaseStatus.loading:
        return [_CenteredSpinner(label: t.auth.payment.loading)];
      case PurchaseStatus.unavailable:
        return [_UnavailableNotice(t: t)];
      case PurchaseStatus.success:
        return [_CenteredSpinner(label: t.auth.payment.activating)];
      case PurchaseStatus.activating:
        return [
          _CenteredSpinner(label: t.auth.payment.activatingAccount),
          const Gap(6),
          Text(
            t.auth.payment.activatingHint,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
        ];
      case PurchaseStatus.ready:
      case PurchaseStatus.busy:
      case PurchaseStatus.processing:
      case PurchaseStatus.error:
        final cardsEnabled = state.status == PurchaseStatus.ready || state.status == PurchaseStatus.error;
        return [
          // Remaining-time explainer: their web-paid days carry over on top of the
          // newly purchased period before the first Play renewal.
          if (remainingDays != null && remainingDays > 0) ...[
            _ExplainerCard(message: t.auth.planTransition.explainer(days: remainingDays)),
            const Gap(16),
          ],
          if (state.status == PurchaseStatus.processing) ...[
            _Banner(message: t.auth.payment.processing, palette: palette),
            const Gap(16),
          ],
          if (state.status == PurchaseStatus.error) ...[
            Text(_errorMessage(t, state.outcome), style: TextStyle(color: theme.colorScheme.error)),
            const Gap(16),
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
            const Gap(12),
          ],
          const Gap(8),
          Text(
            t.auth.payment.autoRenew,
            style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          const Gap(4),
          TextButton(
            onPressed: state.isBusy ? null : notifier.restore,
            child: Text(t.auth.payment.restore),
          ),
        ];
    }
  }

  /// Projected first Play renewal date shown under each plan: today + the user's
  /// remaining paid days + the plan's billing period. This is a display estimate
  /// (the authoritative anchor is set by Google/the backend); for very large
  /// remaining balances Google caps a single `defer` at ~365 days and the backend
  /// chains the rest, so Play's own display may lag this until the chain settles.
  String? _nextRenewalLabel(Translations t, RaynOffer offer, int? remainingDays) {
    if (remainingDays == null) return null;
    final next = projectedRenewal(DateTime.now(), remainingDays, offer.billingPeriodIso);
    return t.auth.planTransition.nextBilling(date: next.formatDate());
  }

  String _errorMessage(Translations t, IapPurchaseOutcome? outcome) {
    switch (outcome) {
      case IapPurchaseOutcome.accountMismatch:
        return t.auth.payment.errorAccountMismatch;
      case IapPurchaseOutcome.tokenInUse:
        return t.auth.payment.errorTokenInUse;
      case IapPurchaseOutcome.ineligible:
        return t.auth.payment.errorIneligible;
      case IapPurchaseOutcome.needsLogin:
        return t.auth.payment.errorNeedsLogin;
      case IapPurchaseOutcome.reauthRequired:
        return t.auth.payment.errorReauth;
      case IapPurchaseOutcome.stillProvisioning:
        return t.auth.payment.errorProvisioning;
      case IapPurchaseOutcome.rateLimited:
        return t.auth.payment.errorRateLimited;
      case IapPurchaseOutcome.unreachable:
        return t.auth.payment.errorUnreachable;
      default:
        return t.auth.payment.errorGeneric;
    }
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
    final theme = Theme.of(context);

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
      await ref.read(loginNotifierProvider.notifier).login(
            email,
            password,
            importProfile: false,
            expectedSubscriptionUrl: expectedSubscriptionUrl,
          );
    }

    ref.listen(loginNotifierProvider, (_, next) {
      if (next.phase == LoginPhase.success) onAuthed();
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          t.auth.planTransition.needsSignIn,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const Gap(20),
        TextField(
          controller: emailCtrl,
          enabled: !isSubmitting,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: t.auth.login.emailLabel,
            prefixIcon: const Icon(Icons.alternate_email),
            border: const OutlineInputBorder(),
          ),
        ),
        const Gap(12),
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
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(obscure.value ? Icons.visibility_off : Icons.visibility),
              onPressed: () => obscure.value = !obscure.value,
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (fieldError.value != null) ...[
          const Gap(8),
          Text(fieldError.value!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (loginState.outcome == LoginOutcome.unreachable) ...[
          const Gap(8),
          AuthUnreachableHelp(t: t),
        ] else if (_outcomeMessage(t, loginState.outcome) case final message?) ...[
          const Gap(8),
          Text(message, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const Gap(24),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: isSubmitting ? null : submit,
            child: isSubmitting
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(t.auth.login.signInButton),
          ),
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

/// Remaining-time explainer card at the top of the plan list.
class _ExplainerCard extends StatelessWidget {
  const _ExplainerCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.rayn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.groupFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule, size: 20, color: theme.colorScheme.primary),
          const Gap(10),
          Expanded(
            child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Info banner (e.g. "payment processing").
class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.palette});

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
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top, size: 20, color: theme.colorScheme.primary),
          const Gap(10),
          Expanded(
            child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: palette.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Shown when Play billing isn't available — points the user to the website.
class _UnavailableNotice extends StatelessWidget {
  const _UnavailableNotice({required this.t});

  final Translations t;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(Icons.storefront_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant),
        const Gap(12),
        Text(t.auth.payment.unavailableTitle, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
        const Gap(8),
        Text(
          t.auth.payment.unavailableBody,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Centered spinner with an optional label (loading / activating states).
class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (label != null) ...[
            const Gap(16),
            Text(label!, style: TextStyle(color: palette.textMuted), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
