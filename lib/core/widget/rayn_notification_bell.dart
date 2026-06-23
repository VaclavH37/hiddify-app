import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/features/notifications/notifier/unread_count_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Glass-wrapped notification bell shared by the Home, Settings, Logs, and
/// About pages. Opens the notifications inbox and shows an unread-count badge.
class RaynNotificationBell extends ConsumerWidget {
  const RaynNotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    final bell = GlassSurface(
      padding: EdgeInsets.zero,
      radius: RaynRadius.button,
      child: Semantics(
        button: true,
        label: 'Notifications',
        child: IconButton(
          icon: Icon(Icons.notifications_none_rounded, color: context.rayn.textPrimary),
          tooltip: 'Notifications',
          onPressed: () => context.goNamed('notifications'),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.button)),
            padding: const EdgeInsets.all(RaynSpacing.sm),
          ),
        ),
      ),
    );

    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: bell,
    );
  }
}
