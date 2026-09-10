import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/sub_page_back_button.dart';
import 'package:hiddify/features/notifications/data/notification_data_providers.dart';
import 'package:hiddify/features/notifications/notifier/notifications_list_notifier.dart';
import 'package:hiddify/features/notifications/widget/notification_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The notifications inbox, reached from the bell. Lists notifications newest
/// first; opening it marks everything seen (clearing the bell badge).
class NotificationsInboxPage extends HookConsumerWidget {
  const NotificationsInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final notifications = ref.watch(notificationsListProvider).valueOrNull ?? const [];
    final palette = context.rayn;

    // Mark everything seen once on open → clears the unread badge.
    useEffect(() {
      Future.microtask(() => ref.read(notificationDataSourceProvider).markAllSeen());
      return null;
    }, const []);

    return RaynPageScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: RaynSpacing.xl),
        children: [
          RaynPageHeader(
            title: t.notifications.title,
            leading: const SubPageBackButton(),
            trailing: [
              if (notifications.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: palette.textPrimary),
                  tooltip: t.notifications.clearAll,
                  onPressed: () => ref.read(notificationDataSourceProvider).deleteAll(),
                ),
            ],
          ),
          if (notifications.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl, vertical: RaynSpacing.xxl),
              child: Center(
                child: Text(t.notifications.empty, style: RaynTypography.body.copyWith(color: palette.textMuted)),
              ),
            )
          else
            for (final notification in notifications) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
                child: NotificationTile(notification: notification, t: t),
              ),
              const SizedBox(height: RaynSpacing.sm),
            ],
        ],
      ),
    );
  }
}
