import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/sub_page_back_button.dart';
import 'package:hiddify/features/auth/register/notifier/resend_verification_notifier.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
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
    final palette = context.rayn;
    final resend = ref.watch(resendVerificationNotifierProvider);
    final hasEmail = email.trim().isNotEmpty;

    final String? resendMessage = switch (resend) {
      ResendStatus.sent => t.auth.verifyEmail.resendSent,
      ResendStatus.failed => t.auth.verifyEmail.resendFailed,
      _ => null,
    };

    return AuthLayout(
      leading: const SubPageBackButton(fallback: 'auth'),
      title: t.auth.verifyEmail.title,
      children: [
        Text(
          hasEmail ? t.auth.verifyEmail.body(email: email.trim()) : t.auth.verifyEmail.bodyGeneric,
          style: RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: palette.textPrimary),
        ),
        const Gap(RaynSpacing.sm),
        Text(
          // On iOS payment happens through StoreKit, not the website, so the
          // note must not send the user to a browser to pay — guideline 3.1.1.
          PlatformUtils.isIOS ? t.auth.verifyEmail.noteApple : t.auth.verifyEmail.note,
          style: RaynTypography.caption.copyWith(color: palette.textMuted),
        ),
        if (resendMessage != null) ...[
          const Gap(RaynSpacing.md),
          Text(
            resendMessage,
            style: RaynTypography.paragraph.copyWith(
              color: resend == ResendStatus.failed ? palette.danger : palette.success,
            ),
          ),
        ],
        const Gap(RaynSpacing.xl),
        if (hasEmail) ...[
          OutlinedButton(
            onPressed: resend == ResendStatus.sending
                ? null
                : () => ref.read(resendVerificationNotifierProvider.notifier).resend(email.trim()),
            child: resend == ResendStatus.sending
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(t.auth.verifyEmail.resend),
          ),
          const Gap(RaynSpacing.md),
        ],
        FilledButton(onPressed: () => context.go('/auth/login'), child: Text(t.auth.verifyEmail.backToLogin)),
        if (!PlatformUtils.isIOS) ...[
          const Gap(RaynSpacing.sm),
          TextButton.icon(
            onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(t.auth.verifyEmail.openWebsite),
          ),
        ],
      ],
    );
  }
}
