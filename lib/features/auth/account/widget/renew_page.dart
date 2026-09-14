import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_notice.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/widget/reauth_panel.dart';
import 'package:hiddify/features/auth/model/billing_period.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/model/purchase_state.dart';
import 'package:hiddify/features/auth/payment/notifier/purchase_notifier.dart';
import 'package:hiddify/features/auth/payment/widget/iap_outcome_message.dart';
import 'package:hiddify/features/auth/payment/widget/legal_links.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';
import 'package:hiddify/features/auth/payment/widget/purchase_progress.dart';
import 'package:hiddify/features/auth/payment/widget/purchase_unavailable_notice.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
import 'package:hiddify/features/auth/widget/logout_confirm.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/utils/date_time_formatter.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Post-auth "your plan has ended" screen at `/renew`.
///
/// Opened by `AccountRedirect` the moment a refresh returns an account
/// verdict, and again from the orb, the home banner, the inbox and Settings.
/// One screen, two modes, driven by the persisted [AccountState]:
///
/// - expired: what ended and when, then the way to renew for this platform —
///   the store's subscription centre and the store plans on mobile (behind an
///   inline sign-in when the device has no session), the website on desktop —
///   plus "Check again" for a renewal made elsewhere;
/// - unavailable: the reason, support, and log out. Never a renew action.
///
/// Leaves on its own once the account is serving again: every persisted
/// config clears the verdict, whichever path produced it.
class RenewPage extends HookConsumerWidget {
  const RenewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final account = ref.watch(accountStateNotifierProvider);

    final checking = useState(false);
    final stillBlocked = useState(false);

    void close() => context.canPop() ? context.pop() : context.go('/home');

    ref.listen(accountStateNotifierProvider, (previous, next) {
      if (next.blocksConnect || !(previous?.blocksConnect ?? false)) return;
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.auth.renew.success);
      context.go('/home');
    });

    // One forced refresh. Its verdict arrives as an account-state change (the
    // listener above leaves the screen) or, when nothing changed, as the
    // "still expired" line under the button.
    Future<void> checkAgain() async {
      stillBlocked.value = false;
      checking.value = true;
      await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
      if (!context.mounted) return;
      checking.value = false;
      stillBlocked.value = ref.read(accountStateNotifierProvider).blocksConnect;
    }

    final title = switch (account) {
      AccountUnavailable() => t.auth.renew.unavailableTitle,
      _ => t.auth.renew.title,
    };

    return AuthLayout(
      leading: IconButton(
        icon: Icon(Icons.close_rounded, color: palette.textPrimary),
        tooltip: t.auth.planTransition.close,
        onPressed: close,
      ),
      title: title,
      children: switch (account) {
        AccountExpired(:final details) => [
          _EndedNotice(t: t, details: details),
          const Gap(RaynSpacing.lg),
          if (PlatformUtils.isDesktop)
            _WebRenewal(t: t, palette: palette)
          else
            _StoreRenewal(t: t, palette: palette, details: details),
          const Gap(RaynSpacing.md),
          _CheckAgain(
            t: t,
            palette: palette,
            checking: checking.value,
            stillBlocked: stillBlocked.value,
            stillBlockedCopy: t.auth.renew.stillExpired,
            onPressed: checkAgain,
          ),
          const Gap(RaynSpacing.xl),
          _LogOut(t: t),
        ],
        AccountUnavailable(:final code) => [
          RaynNotice(tone: RaynNoticeTone.danger, message: _unavailableCopy(t, code)),
          const Gap(RaynSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => UriUtils.tryLaunch(Uri(scheme: 'mailto', path: Constants.supportEmail)),
            icon: const Icon(Icons.mail_outline_rounded),
            label: Text(t.auth.renew.contactSupport),
          ),
          // Only a pending account can change on its own; the others need a
          // person, and a "check again" that never succeeds reads as broken.
          if (code == 'ACCOUNT_PENDING') ...[
            const Gap(RaynSpacing.md),
            _CheckAgain(
              t: t,
              palette: palette,
              checking: checking.value,
              stillBlocked: stillBlocked.value,
              stillBlockedCopy: t.auth.renew.unavailable.pending,
              onPressed: checkAgain,
            ),
          ],
          const Gap(RaynSpacing.xl),
          _LogOut(t: t),
        ],
        AccountActive() => [
          RaynNotice(message: t.auth.renew.activeNotice),
          const Gap(RaynSpacing.lg),
          FilledButton(onPressed: close, child: Text(t.auth.planTransition.close)),
        ],
      },
    );
  }

  /// §7's suggested wording per code; anything unrecognised is "unavailable".
  static String _unavailableCopy(Translations t, String code) => switch (code) {
    'ACCOUNT_SUSPENDED' => t.auth.renew.unavailable.suspended,
    'ACCOUNT_DEACTIVATED' => t.auth.renew.unavailable.deactivated,
    'ACCOUNT_DELETED' => t.auth.renew.unavailable.deleted,
    'ACCOUNT_PENDING' => t.auth.renew.unavailable.pending,
    _ => t.auth.renew.unavailable.body,
  };
}

/// "Your monthly plan ended on 12 Sep 2026." The date only when it is known
/// and already behind us: a 4011 can carry a future date (a store refund ends
/// the account before its paid period does), and that must not read as a
/// countdown.
class _EndedNotice extends StatelessWidget {
  const _EndedNotice({required this.t, required this.details});

  final Translations t;
  final AccountExpiry details;

  @override
  Widget build(BuildContext context) {
    final String message;
    if (details.endedBefore(DateTime.now())) {
      final date = details.expiresAt!.formatDate();
      final plan = billingPeriodLabel(t, details.billingPeriod);
      message = plan == null
          ? t.auth.renew.endedOnNoPlan(date: date)
          : t.auth.renew.endedOn(plan: plan.toLowerCase(), date: date);
    } else {
      message = t.auth.renew.ended;
    }
    return RaynNotice(tone: RaynNoticeTone.warning, message: message);
  }
}

/// Desktop has no billing host: the website is the checkout.
class _WebRenewal extends StatelessWidget {
  const _WebRenewal({required this.t, required this.palette});

  final Translations t;
  final RaynPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.auth.renew.renewHintWeb, style: RaynTypography.paragraph.copyWith(color: palette.textSecondary)),
        const Gap(RaynSpacing.lg),
        FilledButton.icon(
          onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
          icon: const Icon(Icons.open_in_new_rounded),
          label: Text(t.auth.renew.renewOnWebsite),
        ),
      ],
    );
  }
}

/// Mobile: the store's subscription centre for a store-billed plan (fix the
/// payment method), then the store plans — behind an inline sign-in when this
/// device has no session, because verify needs one. Never a link to the
/// account page: that is an external purchase surface, which both stores
/// forbid.
class _StoreRenewal extends HookConsumerWidget {
  const _StoreRenewal({required this.t, required this.palette, required this.details});

  final Translations t;
  final RaynPalette palette;
  final AccountExpiry details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionStore = ref.read(sessionTokenStoreProvider);
    final sessionSnapshot = useFuture(
      useMemoized(() async {
        final token = await sessionStore.read();
        final userId = await sessionStore.readUserId();
        return (token != null && token.isNotEmpty) && (userId != null && userId.isNotEmpty);
      }),
    );
    // null = still resolving; false = sign in first; true = show the plans.
    final authed = useState<bool?>(null);
    if (authed.value == null && sessionSnapshot.hasData) {
      authed.value = sessionSnapshot.data;
    }
    // Known only when the sign-in happened here; a session from an earlier
    // login carries no email.
    final signedInAs = useState<String?>(null);

    final state = ref.watch(purchaseNotifierProvider(false));
    final notifier = ref.read(purchaseNotifierProvider(false).notifier);

    ref.listen(purchaseNotifierProvider(false), (previous, next) {
      if (previous?.status == next.status && previous?.outcome == next.outcome) return;
      // Verify cannot proceed without a fresh session → back to sign-in.
      if (next.status == PurchaseStatus.error &&
          (next.outcome == IapPurchaseOutcome.needsLogin || next.outcome == IapPurchaseOutcome.reauthRequired)) {
        authed.value = false;
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (details.isStoreManaged && details.manageUrl != null) ...[
          OutlinedButton.icon(
            onPressed: () => UriUtils.tryLaunch(details.manageUrl!),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(t.auth.manageSubscription),
          ),
          const Gap(RaynSpacing.lg),
        ],
        if (authed.value == null)
          const PurchaseProgress()
        else if (authed.value == false)
          ReauthPanel(
            t: t,
            needsSignIn: t.auth.renew.needsSignIn,
            onAuthed: (email) {
              signedInAs.value = email;
              authed.value = true;
            },
          )
        else ...[
          if (signedInAs.value case final email?) ...[
            Text(
              t.auth.renew.signedInAs(email: email),
              style: RaynTypography.paragraph.copyWith(color: palette.textSecondary),
            ),
            const Gap(RaynSpacing.md),
          ],
          ..._plans(state, notifier),
        ],
      ],
    );
  }

  List<Widget> _plans(PurchaseState state, PurchaseNotifier notifier) {
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
          Text(t.auth.renew.renewHint, style: RaynTypography.paragraph.copyWith(color: palette.textSecondary)),
          const Gap(RaynSpacing.lg),
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
          // Auto-renewal disclosure on the purchase surface; guideline 2.3.10
          // means the wording must not name the other platform.
          Text(
            PlatformUtils.isIOS ? t.auth.payment.autoRenewApple : t.auth.payment.autoRenew,
            style: RaynTypography.caption.copyWith(color: palette.textMuted),
            textAlign: TextAlign.center,
          ),
          LegalLinks(t: t),
          TextButton(onPressed: state.isBusy ? null : notifier.restore, child: Text(t.auth.payment.restore)),
        ];
    }
  }
}

class _CheckAgain extends StatelessWidget {
  const _CheckAgain({
    required this.t,
    required this.palette,
    required this.checking,
    required this.stillBlocked,
    required this.stillBlockedCopy,
    required this.onPressed,
  });

  final Translations t;
  final RaynPalette palette;
  final bool checking;
  final bool stillBlocked;
  final String stillBlockedCopy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (checking) return PurchaseProgress(label: t.auth.renew.checking);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.refresh_rounded),
          label: Text(t.auth.renew.checkAgain),
        ),
        if (stillBlocked) ...[
          const Gap(RaynSpacing.sm),
          Text(
            stillBlockedCopy,
            style: RaynTypography.paragraph.copyWith(color: palette.danger),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Switching accounts is the other way out of this screen.
class _LogOut extends ConsumerWidget {
  const _LogOut({required this.t});

  final Translations t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton(onPressed: () => confirmLogout(context, ref, t), child: Text(t.auth.logout));
  }
}
