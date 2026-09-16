import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
import 'package:hiddify/features/auth/widget/auth_unreachable_help.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Inline email/password sign-in for post-auth screens that need a session:
/// the router blocks `/auth/*` once a profile exists, so the plan-transition
/// and renewal screens embed this instead of navigating away. Reuses
/// [LoginNotifier] in re-auth mode, which persists a fresh 24h session
/// (token + user_id) without re-importing the profile; [onAuthed] fires with
/// the email that was typed once the session is in place.
///
/// [expectedSubscriptionUrl], when given, is the active profile's URL and the
/// credentials must own it (plan transition). The renewal screen cannot use
/// it — an expired login returns no cryptolink — and passes
/// [expectedAccountId] instead: the account id the middleware attached to the
/// verdict, which the login's `user_id` must equal exactly. Either guard
/// absent means unknown, and the screen shows which account is being renewed.
class ReauthPanel extends HookConsumerWidget {
  const ReauthPanel({
    super.key,
    required this.t,
    required this.needsSignIn,
    required this.onAuthed,
    this.expectedSubscriptionUrl,
    this.expectedAccountId,
  });

  final Translations t;

  /// The one line above the fields saying why a sign-in is needed here.
  final String needsSignIn;

  final ValueChanged<String> onAuthed;
  final String? expectedSubscriptionUrl;
  final String? expectedAccountId;

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
      // profile (the user already has one; the guard would reject it).
      await ref
          .read(loginNotifierProvider.notifier)
          .login(
            email,
            password,
            importProfile: false,
            expectedSubscriptionUrl: expectedSubscriptionUrl,
            expectedAccountId: expectedAccountId,
          );
    }

    ref.listen(loginNotifierProvider, (_, next) {
      if (next.phase == LoginPhase.success) onAuthed(emailCtrl.text.trim());
    });

    final errorStyle = RaynTypography.paragraph.copyWith(color: palette.danger);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(needsSignIn, style: RaynTypography.paragraph.copyWith(color: palette.textSecondary)),
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

  /// Most login outcomes cannot occur on a re-auth (the account exists and is
  /// known); map the ones that can, and fall back to generic.
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
