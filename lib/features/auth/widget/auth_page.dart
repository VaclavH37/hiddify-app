import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/features/auth/notifier/auth_gate_providers.dart';
import 'package:hiddify/features/log/data/diagnostics_exporter.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/alerts.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

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
    final palette = context.rayn;
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
      // Match the connection page canvas (palette.bgPrimary).
      backgroundColor: palette.bgPrimary,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),
                  // Brand wordmark — centered, ~80% of screen width, upper area.
                  const RaynWordmarkHero(),
                  // Subtitle + buttons, vertically centered in the remaining
                  // space (and horizontally centered / full-width).
                  Expanded(
                    flex: 8,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t.auth.subtitle,
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                        const Gap(32),
                        // Primary path: paste the `rayn://import/<token>` link.
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
                        if (!PlatformUtils.isDesktop) ...[
                          const Gap(16),
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
                        ],
                        const Gap(16),
                        // Secondary path: fetch the token via email/password
                        // sign-in. Token import (above) stays primary — it works
                        // even when the account API host is unreachable.
                        _AuthAction(
                          icon: Icons.alternate_email,
                          label: t.auth.login.signInWithEmail,
                          enabled: !isLoading,
                          onTap: () => context.push('/auth/login'),
                        ),
                        const Gap(16),
                        // Create a new account (email verification + payment
                        // finish on the website; the app owns creation only).
                        _AuthAction(
                          icon: Icons.person_add_alt,
                          label: t.auth.register.createAccount,
                          enabled: !isLoading,
                          onTap: () => context.push('/auth/register'),
                        ),
                        if (isLoading) ...[
                          const Gap(24),
                          const Center(child: CircularProgressIndicator()),
                        ],
                        // TEMPORARY — DELETE WHEN THE iOS IMPORT BUG IS CLOSED.
                        //
                        // The same export as Settings → Export diagnostics, hoisted
                        // in front of the auth gate. It is needed here because the
                        // failure being chased happens *during* import, so the user
                        // never reaches Settings, and on iOS the logs are otherwise
                        // unreachable: they live in the App Group container
                        // (FilePath.sharedDirectory), which Xcode's Download
                        // Container does not fetch, and `data/stderr3.log` is the
                        // foreground core's own stderr so it never reaches the
                        // Xcode console either.
                        //
                        // Gated so a normal release cannot carry it, but NOT on
                        // kDebugMode alone: TestFlight rejects debug builds
                        // (`get-task-allow`), and with the Mac in the cloud and no
                        // USB path to the phone, TestFlight is the only way onto a
                        // device — so a kDebugMode-only gate would be unreachable
                        // exactly where it is needed. The dart-define makes an
                        // opted-in RELEASE build possible:
                        //
                        //   make ios-release CHANNEL=prod \
                        //     FF_DART_DEFINES=--build-dart-define=RAYN_DIAGNOSTICS=true
                        //
                        // Absent that flag it compiles out, same as before.
                        //
                        // Removal is this whole `if` block plus the five imports it
                        // added (foundation, directories_provider,
                        // diagnostics_exporter, alerts, share_plus).
                        if (Constants.diagnosticsBuild && PlatformUtils.isMobile) ...[
                          const Gap(16),
                          _AuthAction(
                            icon: Icons.bug_report_outlined,
                            label: t.pages.settings.exportDiagnostics,
                            onTap: () async {
                              final exporter = DiagnosticsExporter(
                                ref.read(appDirectoriesProvider).requireValue.workingDir,
                              );
                              final files = exporter.collect();
                              if (files.isEmpty) {
                                if (context.mounted) {
                                  CustomToast(t.pages.settings.exportDiagnosticsEmpty).show(context);
                                }
                                return;
                              }
                              try {
                                await Share.shareXFiles([
                                  for (final file in files) XFile(file.path, mimeType: "text/plain"),
                                ]);
                              } catch (_) {
                                // Fall back to the clipboard rather than dead-ending.
                                // The share sheet goes through a native plugin and a
                                // UIActivityViewController; when that throws there is
                                // nothing to debug from Dart and no second way off the
                                // device, which is the exact position this button
                                // exists to prevent. The clipboard needs no file URLs
                                // and no reader with App Group access.
                                //
                                // Errors are reported by kind, never by value: a
                                // platform exception can carry absolute paths, and
                                // this is a screen the user may screenshot.
                                final text = exporter.asText();
                                await Clipboard.setData(ClipboardData(text: text));
                                if (context.mounted) {
                                  CustomToast(t.pages.settings.exportDiagnosticsCopied).show(context);
                                }
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
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
      height: 64,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, color: fg, size: 26),
        label: Text(label, style: theme.textTheme.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
