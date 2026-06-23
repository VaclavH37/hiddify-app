import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_colors.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/features/notifications/data/notification_data_providers.dart';
import 'package:hiddify/features/notifications/notifier/notifications_list_notifier.dart';
import 'package:hiddify/features/notifications/widget/notification_copy.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Connection-page alert banner. Shows the newest undismissed notification and
/// stays until the user swipes it away; dismissal keeps the row in the inbox.
class NotificationBanner extends ConsumerWidget {
  const NotificationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final active = ref.watch(activeNotificationsProvider).valueOrNull ?? const [];
    if (active.isEmpty) return const SizedBox.shrink();

    final notification = active.first;
    final copy = notificationCopy(notification, t);
    final palette = context.rayn;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Dismissible(
        key: ValueKey(notification.id),
        onDismissed: (_) => ref.read(notificationDataSourceProvider).markDismissed(notification.id),
        child: GlassSurface(
          glowColor: RaynColors.goldPrimary.withValues(alpha: 0.12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(copy.icon, size: 24, color: RaynColors.goldPrimary),
              const SizedBox(width: RaynSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      copy.title,
                      style: RaynTypography.body.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(copy.body, style: RaynTypography.caption.copyWith(color: palette.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: RaynSpacing.sm),
              Icon(Icons.close_rounded, size: 18, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
