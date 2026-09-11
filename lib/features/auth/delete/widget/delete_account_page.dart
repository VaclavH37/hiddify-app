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
import 'package:hiddify/core/widget/rayn_dialog_action.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';
import 'package:hiddify/core/widget/sub_page_back_button.dart';
import 'package:hiddify/features/auth/delete/model/delete_account_state.dart';
import 'package:hiddify/features/auth/delete/notifier/delete_account_notifier.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Permanent account deletion — App Store guideline 5.1.1(v).
///
/// A full screen rather than a dialog on purpose: the consequences need room to
/// be read, and one of them (a store subscription surviving the account) is
/// something Apple expects the app to state before the user commits.
///
/// The screen has one or two steps depending on how the user authenticated:
///
///  * Signed in with email/password → one step. The stored session authorises
///    the delete; the password field re-confirms it.
///  * Imported a `rayn://` token and never signed in → two steps. There is no
///    session, so the same form also takes an email and signs in first
///    ([LoginNotifier.login] with `importProfile: false`, the same call the
///    plan-transition screen uses), then deletes with the password just typed.
///    The user types their password once either way.
///
/// It is a settings sub-page (the same shape as About), not a pre-auth
/// screen: the user is signed in and got here from Settings → Account. The
/// commit button is red as an outline, not a fill, so amber stays the app's
/// only filled colour; the confirm dialog is the real commit point.
class DeleteAccountPage extends HookConsumerWidget {
  const DeleteAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;

    final deleteState = ref.watch(deleteAccountNotifierProvider);
    final loginState = ref.watch(loginNotifierProvider);
    final busy = deleteState.isSubmitting || loginState.isSubmitting;

    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final remote = profile is RemoteProfileEntity ? profile : null;

    final emailCtrl = useTextEditingController();
    final passwordCtrl = useTextEditingController();
    final obscure = useState(true);
    final fieldError = useState<String?>(null);

    // Whether a session token exists decides if the email field is needed. Read
    // once; `null` while in flight so the form doesn't flicker between shapes.
    final hasSession = useState<bool?>(null);
    useEffect(() {
      var live = true;
      ref.read(sessionTokenStoreProvider).read().then((v) {
        if (live) hasSession.value = v != null;
      });
      return () => live = false;
    }, const []);

    final needsEmail = hasSession.value == false;

    Future<void> submit() async {
      final password = passwordCtrl.text;
      if (password.isEmpty) {
        fieldError.value = t.auth.login.passwordEmpty;
        return;
      }
      if (needsEmail && emailCtrl.text.trim().isEmpty) {
        fieldError.value = t.auth.login.emailEmpty;
        return;
      }
      fieldError.value = null;

      // Final confirmation. The form itself is not the commit point: the button
      // above only gets you here, and this dialog is what actually authorises an
      // irreversible delete.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog.adaptive(
          title: Text(t.auth.deleteAccount.confirmTitle),
          content: Text(t.auth.deleteAccount.confirmBody),
          actions: [
            raynDialogAction(ctx, label: t.auth.deleteAccount.cancel, onPressed: () => Navigator.of(ctx).pop(false)),
            raynDialogAction(
              ctx,
              label: t.auth.deleteAccount.confirmProceed,
              onPressed: () => Navigator.of(ctx).pop(true),
              destructive: true,
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      if (needsEmail) {
        // Establish a session without re-importing the profile: the user
        // already has one, and the import guard would reject a second.
        await ref
            .read(loginNotifierProvider.notifier)
            .login(emailCtrl.text.trim(), password, importProfile: false, expectedSubscriptionUrl: remote?.url);
        return; // the listener below continues into the delete on success
      }
      await ref.read(deleteAccountNotifierProvider.notifier).deleteAccount(password);
    }

    // Sign-in step succeeded → go straight into the delete with the password
    // already in hand, so the user is not asked for it twice.
    ref.listen(loginNotifierProvider, (_, next) {
      if (next.phase == LoginPhase.success) {
        hasSession.value = true;
        ref.read(deleteAccountNotifierProvider.notifier).deleteAccount(passwordCtrl.text);
      }
    });

    // On success the notifier has already torn the profile down, so the router
    // redirect replaces this screen with /auth. Only the toast is ours.
    ref.listen(deleteAccountNotifierProvider, (_, next) {
      if (next.phase == DeleteAccountPhase.success) {
        ref.read(inAppNotificationControllerProvider).showSuccessToast(t.auth.deleteAccount.done);
      }
    });

    final outcomeMessage = _outcomeMessage(t, deleteState.outcome);
    final errorStyle = RaynTypography.paragraph.copyWith(color: palette.danger);
    final consequences = [
      t.auth.deleteAccount.consequencePermanent,
      t.auth.deleteAccount.consequenceDevice,
      t.auth.deleteAccount.consequenceStore,
    ];

    return RaynPageScaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuthLayout.maxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, 0, RaynSpacing.xl, RaynSpacing.xl),
            children: [
              RaynPageHeader(
                title: t.auth.deleteAccount.title,
                padding: const EdgeInsets.only(top: RaynSpacing.xl, bottom: RaynSpacing.lg),
                leading: const SubPageBackButton(fallback: 'settings'),
              ),
              Text(
                t.auth.deleteAccount.subtitle,
                style: RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: palette.textSecondary),
              ),
              const Gap(RaynSpacing.lg),
              // What deletion actually does, stated before the user commits:
              // three sentences on one card, no icons, no red tint.
              RaynSurface(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, line) in consequences.indexed) ...[
                      if (i > 0) const Divider(indent: RaynSpacing.lg, endIndent: RaynSpacing.lg),
                      Padding(
                        padding: const EdgeInsets.all(RaynSpacing.lg),
                        child: Text(line, style: RaynTypography.paragraph.copyWith(color: palette.textPrimary)),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(RaynSpacing.xl),
              if (needsEmail) ...[
                Text(
                  t.auth.deleteAccount.needsSignIn,
                  style: RaynTypography.paragraph.copyWith(color: palette.textSecondary),
                ),
                const Gap(RaynSpacing.md),
                TextField(
                  controller: emailCtrl,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: t.auth.login.emailLabel,
                    prefixIcon: const Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const Gap(RaynSpacing.md),
              ],
              TextField(
                controller: passwordCtrl,
                enabled: !busy,
                obscureText: obscure.value,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  labelText: t.auth.deleteAccount.passwordLabel,
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(obscure.value ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    onPressed: () => obscure.value = !obscure.value,
                  ),
                ),
              ),
              if (fieldError.value != null) ...[const Gap(RaynSpacing.sm), Text(fieldError.value!, style: errorStyle)],
              if (outcomeMessage != null) ...[const Gap(RaynSpacing.sm), Text(outcomeMessage, style: errorStyle)],
              const Gap(RaynSpacing.xl),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.danger,
                  side: BorderSide(color: palette.danger),
                ),
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t.auth.deleteAccount.confirmAction),
              ),
              const Gap(RaynSpacing.sm),
              TextButton(onPressed: busy ? null : () => context.pop(), child: Text(t.auth.deleteAccount.cancel)),
              const Gap(RaynSpacing.lg),
              // Escape hatch for an account that cannot sign in — a token
              // issued without credentials, or a forgotten password. The
              // in-app path above is what 5.1.1(v) requires; this is for the
              // cases it cannot serve.
              Text(
                t.auth.deleteAccount.supportHint,
                style: RaynTypography.caption.copyWith(color: palette.textMuted),
                textAlign: TextAlign.center,
              ),
              const Gap(RaynSpacing.xs),
              TextButton(
                onPressed: () => UriUtils.tryLaunch(Uri.parse('mailto:${Constants.supportEmail}')),
                child: const Text(Constants.supportEmail),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _outcomeMessage(Translations t, DeleteAccountOutcome? outcome) {
    switch (outcome) {
      case DeleteAccountOutcome.invalidPassword:
        return t.auth.deleteAccount.errorPassword;
      case DeleteAccountOutcome.needsLogin:
        return t.auth.deleteAccount.errorNeedsLogin;
      case DeleteAccountOutcome.accountLocked:
        return t.auth.deleteAccount.errorAccountLocked;
      case DeleteAccountOutcome.paymentInFlight:
        return t.auth.deleteAccount.errorPaymentInFlight;
      case DeleteAccountOutcome.rateLimited:
        return t.auth.deleteAccount.errorRateLimited;
      case DeleteAccountOutcome.unreachable:
        return t.auth.deleteAccount.errorUnreachable;
      case DeleteAccountOutcome.generic:
        return t.auth.deleteAccount.errorGeneric;
      case null:
        return null;
    }
  }
}
