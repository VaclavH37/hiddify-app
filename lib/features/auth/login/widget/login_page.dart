import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/sub_page_back_button.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
import 'package:hiddify/features/auth/widget/auth_unreachable_help.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Optional email/password sign-in. On success it imports the fetched
/// `rayn://import/<token>` via the shared import path and the router redirect
/// (driven by `hasAnyProfileProvider`) swaps this screen for `/home`.
class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
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
      await ref.read(loginNotifierProvider.notifier).login(email, password);
    }

    // Some outcomes navigate instead of rendering an inline message:
    //  - `EMAIL_NOT_VERIFIED` → the verify screen (carrying the typed email so
    //    resend works).
    //  - `pending_payment` → the pricing screen (the account is verified but has
    //    no subscription to import yet).
    //  - `expired` → the same pricing screen, flagged as the expired variant so
    //    it shows a "subscription expired — renew" notice.
    ref.listen(loginNotifierProvider, (_, next) {
      switch (next.outcome) {
        case LoginOutcome.emailNotVerified:
          context.push('/auth/verify-email', extra: emailCtrl.text.trim());
        case LoginOutcome.pendingPayment:
          context.push('/auth/payment', extra: false);
        case LoginOutcome.expired:
          context.push('/auth/payment', extra: true);
        default:
          break;
      }
    });

    final outcomeMessage = _outcomeMessage(t, loginState.outcome);
    final errorStyle = RaynTypography.paragraph.copyWith(color: palette.danger);

    return AuthLayout(
      leading: const SubPageBackButton(fallback: 'auth'),
      title: t.auth.login.signInWithEmail,
      children: [
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
        // When the host is unreachable (e.g. packet-filtered) the failure is
        // never silent: show retry / token / support help.
        if (loginState.outcome == LoginOutcome.unreachable) ...[
          const Gap(RaynSpacing.md),
          AuthUnreachableHelp(t: t),
        ] else if (outcomeMessage != null) ...[
          const Gap(RaynSpacing.sm),
          Text(outcomeMessage, style: errorStyle),
          if (_showWebsiteLink(loginState.outcome)) ...[
            const Gap(RaynSpacing.xs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(t.auth.login.openWebsite),
              ),
            ),
          ],
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

  String? _outcomeMessage(Translations t, LoginOutcome? outcome) {
    switch (outcome) {
      case null:
        return null;
      case LoginOutcome.invalidCredentials:
        return t.auth.login.invalidCredentials;
      case LoginOutcome.emailNotVerified:
        // Handled by a redirect to the verification screen, not an inline message.
        return null;
      case LoginOutcome.accountSuspended:
        // The stock copy tells the user to visit their account page. On iOS
        // that page is an external purchase surface, so point at support
        // instead — guideline 3.1.1.
        return PlatformUtils.isIOS ? t.auth.login.accountSuspendedApple : t.auth.login.accountSuspended;
      case LoginOutcome.accountDeactivated:
        return t.auth.login.accountDeactivated;
      case LoginOutcome.pendingPayment:
      case LoginOutcome.expired:
        // Handled by a redirect to the pricing screen, not an inline message.
        return null;
      case LoginOutcome.pendingActivation:
        return t.auth.login.pendingActivation;
      case LoginOutcome.verifyFailed:
        return t.auth.login.verifyFailed;
      case LoginOutcome.unreachable:
        // Rendered by AuthUnreachableHelp (with recovery actions), not inline.
        return null;
      case LoginOutcome.accountMismatch:
        // Only the plan-transition re-auth sets this; never reached here.
        return null;
      case LoginOutcome.updateRequired:
        return t.auth.login.updateRequired;
      case LoginOutcome.generic:
        return t.auth.login.generic;
    }
  }

  bool _showWebsiteLink(LoginOutcome? outcome) {
    // Never on iOS: the account page exposes an external way to pay, and
    // linking to one from inside the app is a guideline 3.1.1 rejection. Same
    // rule the purchase-unavailable notice already applies.
    if (PlatformUtils.isIOS) return false;
    switch (outcome) {
      case LoginOutcome.accountSuspended:
      case LoginOutcome.accountDeactivated:
        return true;
      default:
        return false;
    }
  }
}
