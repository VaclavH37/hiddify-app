import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/auth/delete/model/delete_account_state.dart';
import 'package:hiddify/features/auth/delete/notifier/delete_account_notifier.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/login_state.dart';
import 'package:hiddify/features/auth/login/notifier/login_notifier.dart';
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
class DeleteAccountPage extends HookConsumerWidget {
  const DeleteAccountPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
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
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.auth.deleteAccount.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.auth.deleteAccount.confirmProceed),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      if (needsEmail) {
        // Establish a session without re-importing the profile: the user
        // already has one, and the import guard would reject a second.
        await ref.read(loginNotifierProvider.notifier).login(
              emailCtrl.text.trim(),
              password,
              importProfile: false,
              expectedSubscriptionUrl: remote?.url,
            );
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

    return Scaffold(
      appBar: AppBar(title: Text(t.auth.deleteAccount.title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t.auth.deleteAccount.subtitle, style: theme.textTheme.bodyLarge),
                  const Gap(20),
                  _ConsequenceCard(t: t, palette: palette, theme: theme),
                  const Gap(20),
                  if (needsEmail) ...[
                    Text(
                      t.auth.deleteAccount.needsSignIn,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const Gap(12),
                    TextField(
                      controller: emailCtrl,
                      enabled: !busy,
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
                  ],
                  const Gap(24),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: palette.danger),
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(t.auth.deleteAccount.confirmAction),
                    ),
                  ),
                  const Gap(8),
                  TextButton(
                    onPressed: busy ? null : () => context.pop(),
                    child: Text(t.auth.deleteAccount.cancel),
                  ),
                  const Gap(16),
                  // Escape hatch for an account that cannot sign in — a token
                  // issued without credentials, or a forgotten password. The
                  // in-app path above is what 5.1.1(v) requires; this is for the
                  // cases it cannot serve.
                  Text(
                    t.auth.deleteAccount.supportHint,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(4),
                  TextButton(
                    onPressed: () => UriUtils.tryLaunch(Uri.parse('mailto:${Constants.supportEmail}')),
                    child: const Text(Constants.supportEmail),
                  ),
                ],
              ),
            ),
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

/// What deletion actually does, stated before the user commits.
class _ConsequenceCard extends StatelessWidget {
  const _ConsequenceCard({required this.t, required this.palette, required this.theme});

  final Translations t;
  final RaynPalette palette;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final items = [
      t.auth.deleteAccount.consequencePermanent,
      t.auth.deleteAccount.consequenceDevice,
      t.auth.deleteAccount.consequenceStore,
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.08),
        border: Border.all(color: palette.danger.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, line) in items.indexed) ...[
            if (i > 0) const Gap(10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: palette.danger),
                const Gap(10),
                Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
