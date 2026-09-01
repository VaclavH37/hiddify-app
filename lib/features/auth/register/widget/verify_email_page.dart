import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/features/auth/register/notifier/resend_verification_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// "Check your email to verify your account" screen. Reached from a successful
/// registration and from the "email not verified" login redirect — both pass
/// the typed email so the resend button works. Verification itself completes
/// on the website.
class VerifyEmailPage extends ConsumerWidget {
  const VerifyEmailPage({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final palette = context.rayn;
    final resend = ref.watch(resendVerificationNotifierProvider);
    final hasEmail = email.trim().isNotEmpty;

    final String? resendMessage = switch (resend) {
      ResendStatus.sent => t.auth.verifyEmail.resendSent,
      ResendStatus.failed => t.auth.verifyEmail.resendFailed,
      _ => null,
    };

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
                    Icon(Icons.mark_email_unread_outlined, size: 48, color: palette.textSecondary),
                    const Gap(16),
                    Text(
                      t.auth.verifyEmail.title,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const Gap(12),
                    Text(
                      hasEmail ? t.auth.verifyEmail.body(email: email.trim()) : t.auth.verifyEmail.bodyGeneric,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const Gap(8),
                    Text(
                      // On iOS payment happens through StoreKit, not the
                      // website, so the note must not send the user to a
                      // browser to pay — guideline 3.1.1.
                      PlatformUtils.isIOS ? t.auth.verifyEmail.noteApple : t.auth.verifyEmail.note,
                      style: theme.textTheme.bodySmall?.copyWith(color: palette.textMuted),
                      textAlign: TextAlign.center,
                    ),
                    if (resendMessage != null) ...[
                      const Gap(12),
                      Text(
                        resendMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: resend == ResendStatus.failed ? theme.colorScheme.error : palette.success,
                        ),
                      ),
                    ],
                    const Gap(24),
                    if (hasEmail)
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: resend == ResendStatus.sending
                              ? null
                              : () => ref.read(resendVerificationNotifierProvider.notifier).resend(email.trim()),
                          child: resend == ResendStatus.sending
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(t.auth.verifyEmail.resend),
                        ),
                      ),
                    const Gap(12),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () => context.go('/auth/login'),
                        child: Text(t.auth.verifyEmail.backToLogin),
                      ),
                    ),
                    const Gap(8),
                    if (!PlatformUtils.isIOS)
                      TextButton.icon(
                        onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(t.auth.verifyEmail.openWebsite),
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
}
