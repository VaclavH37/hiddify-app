import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
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
      await ref.read(loginNotifierProvider.notifier).login(email, password);
    }

    final outcomeMessage = _outcomeMessage(t, loginState.outcome);

    return Scaffold(
      appBar: AppBar(title: Text(t.auth.login.title)),
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
                    Text(t.auth.login.subtitle, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
                    const Gap(24),
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
                    if (outcomeMessage != null) ...[
                      const Gap(8),
                      Text(outcomeMessage, style: TextStyle(color: theme.colorScheme.error)),
                      if (_showWebsiteLink(loginState.outcome)) ...[
                        const Gap(4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: Text(t.auth.login.openWebsite),
                          ),
                        ),
                      ],
                    ],
                    const Gap(24),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: isSubmitting ? null : submit,
                        child: isSubmitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(t.auth.login.signInButton),
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

  String? _outcomeMessage(Translations t, LoginOutcome? outcome) {
    switch (outcome) {
      case null:
        return null;
      case LoginOutcome.invalidCredentials:
        return t.auth.login.invalidCredentials;
      case LoginOutcome.emailNotVerified:
        return t.auth.login.emailNotVerified;
      case LoginOutcome.accountSuspended:
        return t.auth.login.accountSuspended;
      case LoginOutcome.accountDeactivated:
        return t.auth.login.accountDeactivated;
      case LoginOutcome.pendingPayment:
        return t.auth.login.pendingPayment;
      case LoginOutcome.pendingActivation:
        return t.auth.login.pendingActivation;
      case LoginOutcome.verifyFailed:
        return t.auth.login.verifyFailed;
      case LoginOutcome.unreachable:
        return t.auth.login.unreachable;
      case LoginOutcome.generic:
        return t.auth.login.generic;
    }
  }

  bool _showWebsiteLink(LoginOutcome? outcome) {
    switch (outcome) {
      case LoginOutcome.emailNotVerified:
      case LoginOutcome.accountSuspended:
      case LoginOutcome.accountDeactivated:
      case LoginOutcome.pendingPayment:
        return true;
      default:
        return false;
    }
  }
}
