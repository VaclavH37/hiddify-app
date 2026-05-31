import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/auth/notifier/auth_gate_providers.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// First-screen the user sees when no profile is imported. Hosts the QR
/// scanner (mobile only) and clipboard-paste affordances; both pipe into
/// the existing `addClipboard` validation, which only accepts
/// `rayn://import/<token>` links.
class AuthPage extends HookConsumerWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = (constraints.maxWidth * 0.4).clamp(96.0, 200.0);
                      return Assets.images.logo.svg(width: size, height: size);
                    },
                  ),
                  const Gap(24),
                  Text(t.auth.title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const Gap(8),
                  Text(
                    t.auth.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(32),
                  if (!PlatformUtils.isDesktop) ...[
                    _AuthAction(
                      icon: Icons.qr_code_scanner,
                      label: t.auth.scanQr,
                      enabled: !isLoading,
                      onTap: () async {
                        final result = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
                        if (result == null || !context.mounted) return;
                        await ref.read(addProfileNotifierProvider.notifier).addClipboard(result);
                      },
                    ),
                    const Gap(12),
                  ],
                  _AuthAction(
                    icon: Icons.content_paste,
                    label: t.auth.paste,
                    enabled: !isLoading,
                    primary: true,
                    onTap: () async {
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
                    },
                  ),
                  if (isLoading) ...[const Gap(24), const CircularProgressIndicator()],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthAction extends StatelessWidget {
  const _AuthAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = primary ? theme.colorScheme.onPrimary : theme.colorScheme.primary;
    final bg = primary ? theme.colorScheme.primary : Colors.transparent;
    final borderColor = primary ? theme.colorScheme.primary : theme.colorScheme.outlineVariant;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, color: fg),
        label: Text(label, style: theme.textTheme.titleMedium?.copyWith(color: fg)),
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
