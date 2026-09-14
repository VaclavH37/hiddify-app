import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/notifications/widget/notification_copy.dart';
import 'package:hiddify/utils/date_time_formatter.dart';

/// One row in the notifications inbox.
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.notification, required this.t});

  final AppNotification notification;
  final Translations t;

  @override
  Widget build(BuildContext context) {
    final copy = notificationCopy(notification, t);
    final palette = context.rayn;
    // An account verdict's row opens the renewal screen; the others are records.
    final renewable = notification.kind.opensRenewal;

    final surface = RaynSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(copy.icon, size: 24, color: notificationTint(copy, palette)),
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
                const SizedBox(height: RaynSpacing.xs),
                Text(
                  notification.createdAt.formatDate(),
                  style: RaynTypography.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
          if (renewable) Icon(Icons.chevron_right_rounded, color: palette.textMuted),
        ],
      ),
    );
    if (!renewable) return surface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.pushNamed('renew'),
      child: surface,
    );
  }
}
