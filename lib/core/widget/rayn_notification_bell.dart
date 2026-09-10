import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/notifications/notifier/unread_count_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The notifications bell, shared by Home, Settings, About and the picker:
/// a plain icon button with an unread badge. It used to sit in its own
/// filled, rounded box; a button in a box in a bar is one container too many.
class RaynNotificationBell extends ConsumerWidget {
  const RaynNotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final unread = ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0;

    return Badge(
      isLabelVisible: unread > 0,
      label: Text(unread > 99 ? '99+' : '$unread'),
      child: IconButton(
        icon: Icon(Icons.notifications_none_rounded, color: context.rayn.textPrimary),
        tooltip: t.notifications.title,
        onPressed: () => context.goNamed('notifications'),
      ),
    );
  }
}
