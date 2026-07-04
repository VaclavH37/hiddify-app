import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/features/auth/register/model/register_state.dart';
import 'package:hiddify/features/auth/register/model/register_validators.dart';
import 'package:hiddify/features/auth/register/notifier/register_notifier.dart';
import 'package:hiddify/features/auth/widget/auth_unreachable_help.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// In-app account creation. Mirrors the login page's styling. On success it
/// advances to the email-verification screen; account creation alone never
/// imports a token (the user finishes verification + payment on the website).
class RegisterPage extends HookConsumerWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final palette = context.rayn;

    final registerState = ref.watch(registerNotifierProvider);
    final isSubmitting = registerState.isSubmitting;

    final emailCtrl = useTextEditingController();
    final passwordCtrl = useTextEditingController();
    final displayNameCtrl = useTextEditingController();
    final obscure = useState(true);

    final emailError = useState<String?>(null);
    final passwordError = useState<String?>(null);
    final displayNameError = useState<String?>(null);

    String? msgFor(RegisterFieldError? e) => e == null ? null : _fieldErrorMessage(t, e);

    // On a successful create, advance to the verify-email screen carrying the
    // typed email (so resend works). pushReplacement drops the form from history.
    ref.listen(registerNotifierProvider, (_, next) {
      if (next.phase == RegisterPhase.success) {
        context.pushReplacement('/auth/verify-email', extra: emailCtrl.text.trim());
      }
    });

    Future<void> submit() async {
      final email = emailCtrl.text.trim();
      final password = passwordCtrl.text;
      final displayName = displayNameCtrl.text.trim();

      emailError.value = msgFor(RegisterValidators.email(email));
      passwordError.value = msgFor(RegisterValidators.password(password));
      displayNameError.value = msgFor(RegisterValidators.displayName(displayName));
      if (emailError.value != null || passwordError.value != null || displayNameError.value != null) {
        return;
      }
      await ref.read(registerNotifierProvider.notifier).register(email, password, displayName);
    }

    final outcomeMessage = _outcomeMessage(t, registerState);
    final isUnreachable =
        registerState.phase == RegisterPhase.outcome && registerState.outcome == RegisterOutcome.unreachable;

    return Scaffold(
      backgroundColor: palette.bgPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
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
                    const Gap(24),
                    const RaynWordmarkHero(),
                    const Gap(36),
                    Text(t.auth.register.subtitle, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                    const Gap(24),
                    TextField(
                      controller: emailCtrl,
                      enabled: !isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: t.auth.register.emailLabel,
                        prefixIcon: const Icon(Icons.alternate_email),
                        border: const OutlineInputBorder(),
                        errorText: emailError.value,
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: passwordCtrl,
                      enabled: !isSubmitting,
                      obscureText: obscure.value,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: t.auth.register.passwordLabel,
                        helperText: t.auth.register.passwordRule,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscure.value ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => obscure.value = !obscure.value,
                        ),
                        border: const OutlineInputBorder(),
                        errorText: passwordError.value,
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: displayNameCtrl,
                      enabled: !isSubmitting,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: t.auth.register.displayNameLabel,
                        helperText: t.auth.register.displayNameRule,
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: const OutlineInputBorder(),
                        errorText: displayNameError.value,
                      ),
                    ),
                    // Unreachable host (e.g. packet-filtered): never silent —
                    // offer retry / token-import / support recovery paths.
                    if (isUnreachable) ...[
                      const Gap(12),
                      AuthUnreachableHelp(t: t),
                    ] else if (outcomeMessage != null) ...[
                      const Gap(12),
                      Text(outcomeMessage, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                    const Gap(24),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: isSubmitting ? null : submit,
                        child: isSubmitting
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(t.auth.register.submit),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _fieldErrorMessage(Translations t, RegisterFieldError e) {
    switch (e) {
      case RegisterFieldError.emailRequired:
        return t.auth.register.emailRequired;
      case RegisterFieldError.emailInvalid:
        return t.auth.register.emailInvalid;
      case RegisterFieldError.passwordRequired:
        return t.auth.register.passwordRequired;
      case RegisterFieldError.passwordTooShort:
        return t.auth.register.passwordTooShort;
      case RegisterFieldError.passwordTooLong:
        return t.auth.register.passwordTooLong;
      case RegisterFieldError.displayNameRequired:
        return t.auth.register.displayNameRequired;
      case RegisterFieldError.displayNameTooLong:
        return t.auth.register.displayNameTooLong;
      case RegisterFieldError.displayNameInvalid:
        return t.auth.register.displayNameInvalid;
    }
  }

  String? _outcomeMessage(Translations t, RegisterState s) {
    if (s.phase != RegisterPhase.outcome) return null;
    switch (s.outcome) {
      case RegisterOutcome.validationError:
        return s.serverMessage ?? t.auth.register.generic;
      case RegisterOutcome.tooManyRequests:
        return t.auth.register.tooManyRequests;
      case RegisterOutcome.verifyFailed:
        return t.auth.register.verifyFailed;
      case RegisterOutcome.unreachable:
        // Rendered by AuthUnreachableHelp (with recovery actions), not inline.
        return null;
      case RegisterOutcome.generic:
      case null:
        return t.auth.register.generic;
    }
  }
}
