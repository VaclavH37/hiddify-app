import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/features/auth/notifier/auth_gate_providers.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';
import 'package:hiddify/features/log/widget/export_diagnostics.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// First screen the user sees when no profile is imported. Hosts the QR
/// scanner (mobile only) and clipboard-paste affordances; both pipe into
/// the existing `addClipboard` validation, which only accepts
/// `rayn://import/<token>` links.
///
/// The wordmark and the actions are one group, centred on the screen by the
/// layout. There is no tagline: four labelled buttons explain themselves.
class AuthPage extends HookConsumerWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isLoading = ref.watch(addProfileNotifierProvider).isLoading;

    // Cold-start deep link consumption: if a `rayn://` URL was captured by
    // the redirect before this screen mounted, auto-import on first build.
    useEffect(() {
      final pending = ref.read(pendingDeepLinkUrlProvider);
      if (pending != null) {
        ref.read(pendingDeepLinkUrlProvider.notifier).state = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(addProfileNotifierProvider.notifier).addClipboard(pending);
          }
        });
      }
      return null;
    }, const []);

    Future<void> paste() async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text ?? '';
      if (raw.isEmpty) {
        if (context.mounted) {
          ref.read(inAppNotificationControllerProvider).showErrorToast(t.auth.pasteEmpty);
        }
        return;
      }
      if (!context.mounted) return;
      await ref.read(addProfileNotifierProvider.notifier).addClipboard(raw);
    }

    Future<void> scan() async {
      final result = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
      if (result == null || !context.mounted) return;
      await ref.read(addProfileNotifierProvider.notifier).addClipboard(result);
    }

    return AuthLayout(
      children: [
        // Primary path: paste the `rayn://import/<token>` link.
        FilledButton.icon(
          style: AppTheme.largeButton,
          onPressed: isLoading ? null : paste,
          icon: const Icon(Icons.content_paste_rounded),
          label: Text(t.auth.paste),
        ),
        if (!PlatformUtils.isDesktop) ...[
          const Gap(RaynSpacing.lg),
          OutlinedButton.icon(
            style: AppTheme.largeButton,
            onPressed: isLoading ? null : scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(t.auth.scanQr),
          ),
        ],
        const Gap(RaynSpacing.lg),
        // Secondary path: fetch the token via email/password sign-in. Token
        // import (above) stays primary — it works even when the account API
        // host is unreachable.
        OutlinedButton.icon(
          style: AppTheme.largeButton,
          onPressed: isLoading ? null : () => context.push('/auth/login'),
          icon: const Icon(Icons.alternate_email_rounded),
          label: Text(t.auth.login.signInWithEmail),
        ),
        const Gap(RaynSpacing.lg),
        // Create a new account (email verification + payment finish on the
        // website; the app owns creation only).
        OutlinedButton.icon(
          style: AppTheme.largeButton,
          onPressed: isLoading ? null : () => context.push('/auth/register'),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(t.auth.register.createAccount),
        ),
        // Diagnostics builds only, and it has to live HERE.
        //
        // A core that fails to initialise is swallowed by
        // `_safeInit("rayn-core")` (bootstrap.dart) and surfaces as an
        // import failure on this screen — but Settings is unreachable until
        // a profile exists, so the export in Settings cannot be reached to
        // find out why. Relaunching does not help either:
        // `LogRepository.init()` truncates app.log and core.log on every
        // launch, so the run that failed is gone by the time Settings is
        // reachable.
        //
        // An earlier copy of this was removed in 4cf52f7c as "temporary"
        // once that bug looked closed. It was not. Gated on
        // `Constants.diagnosticsBuild` so a shipping release cannot show it —
        // the same single gate that decides whether any logs get written at
        // all.
        if (Constants.diagnosticsBuild && PlatformUtils.isMobile) ...[
          const Gap(RaynSpacing.md),
          TextButton.icon(
            onPressed: () => exportDiagnostics(context, ref, t),
            icon: const Icon(Icons.share_rounded),
            label: Text(t.pages.settings.exportDiagnostics),
          ),
        ],
        if (isLoading) ...[
          const Gap(RaynSpacing.xl),
          const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      ],
    );
  }
}
