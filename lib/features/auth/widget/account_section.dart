import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/auth/notifier/logout_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Settings → Account block. Three stacked [RaynSettingsTile]s:
/// profile + refresh, Copy-Token (gated on the original token still being on
/// disk), and a destructive Logout. Loading indicator renders below when the
/// logout request is in flight.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final profileAsync = ref.watch(activeProfileProvider);
    final logoutLoading = ref.watch(logoutNotifierProvider).isLoading;

    final profile = profileAsync.valueOrNull;
    if (profile == null) return const SizedBox.shrink();

    final remote = profile is RemoteProfileEntity ? profile : null;
    final sourceToken = remote?.sourceToken;
    final subInfoLine = remote?.subInfo != null ? _formatSubInfo(remote!) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaynSettingsTile(
            leading: Icons.account_circle_outlined,
            title: profile.name,
            subtitle: subInfoLine,
            trailing: IconButton(
              tooltip: t.pages.profiles.update,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () =>
                  ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            ),
          ),
          const SizedBox(height: RaynSpacing.sm),
          RaynSettingsTile(
            leading: Icons.content_copy,
            title: t.auth.copyToken,
            subtitle: sourceToken == null ? t.auth.noTokenStored : null,
            enabled: sourceToken != null && !logoutLoading,
            onTap: sourceToken == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: sourceToken));
                    if (!context.mounted) return;
                    ref
                        .read(inAppNotificationControllerProvider)
                        .showSuccessToast(t.auth.tokenCopied);
                  },
          ),
          const SizedBox(height: RaynSpacing.sm),
          RaynSettingsTile(
            leading: Icons.logout,
            title: t.auth.logout,
            accentColor: palette.danger,
            enabled: !logoutLoading,
            onTap: () => _confirmLogout(context, ref, t),
          ),
          if (logoutLoading)
            const Padding(
              padding: EdgeInsets.only(top: RaynSpacing.sm),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref, Translations t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(t.auth.logoutConfirmTitle),
        content: Text(t.auth.logoutConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.auth.logoutCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.auth.logoutConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(logoutNotifierProvider.notifier).logout();
    }
  }
}

String _formatSubInfo(RemoteProfileEntity profile) {
  final sub = profile.subInfo!;
  final consumed = sub.consumption.sizeGB();
  final total = sub.total.sizeGB();
  final daysLeft = sub.remaining.inDays;
  final expiry = sub.isExpired
      ? 'expired'
      : daysLeft > 365
      ? '∞'
      : '${daysLeft}d';
  return '$consumed / $total GB · $expiry';
}

extension _SizeFmt on int {
  String sizeGB() => (this / (1024 * 1024 * 1024)).toStringAsFixed(2);
}
