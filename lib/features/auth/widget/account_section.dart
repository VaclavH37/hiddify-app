import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/auth/notifier/logout_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Settings → Account block. Shows the active profile name + sub-info,
/// a Refresh button, the Copy-Token button (only if the original token is
/// still on disk), and a destructive Logout button.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final profileAsync = ref.watch(activeProfileProvider);
    final logoutLoading = ref.watch(logoutNotifierProvider).isLoading;

    final profile = profileAsync.valueOrNull;
    if (profile == null) return const SizedBox.shrink();

    final remote = profile is RemoteProfileEntity ? profile : null;
    final sourceToken = remote?.sourceToken;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            t.auth.account,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(profile.name),
          subtitle: remote?.subInfo == null ? null : _SubInfoLine(remote!),
          trailing: IconButton(
            tooltip: t.pages.profiles.update,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.content_copy),
          title: Text(t.auth.copyToken),
          subtitle: sourceToken == null ? Text(t.auth.noTokenStored, style: theme.textTheme.bodySmall) : null,
          enabled: sourceToken != null && !logoutLoading,
          onTap: sourceToken == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: sourceToken));
                  if (!context.mounted) return;
                  ref.read(inAppNotificationControllerProvider).showSuccessToast(t.auth.tokenCopied);
                },
        ),
        const Divider(indent: 16, endIndent: 16),
        ListTile(
          leading: Icon(Icons.logout, color: theme.colorScheme.error),
          title: Text(t.auth.logout, style: TextStyle(color: theme.colorScheme.error)),
          enabled: !logoutLoading,
          onTap: () => _confirmLogout(context, ref, t),
        ),
        if (logoutLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(),
          ),
        const Gap(8),
      ],
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

class _SubInfoLine extends StatelessWidget {
  const _SubInfoLine(this.profile);
  final RemoteProfileEntity profile;

  @override
  Widget build(BuildContext context) {
    final sub = profile.subInfo!;
    final consumed = sub.consumption.sizeGB();
    final total = sub.total.sizeGB();
    final daysLeft = sub.remaining.inDays;
    final expiry = sub.isExpired
        ? 'expired'
        : daysLeft > 365
        ? '∞'
        : '${daysLeft}d';
    return Text('$consumed / $total GB · $expiry');
  }
}

extension _SizeFmt on int {
  String sizeGB() => (this / (1024 * 1024 * 1024)).toStringAsFixed(2);
}
