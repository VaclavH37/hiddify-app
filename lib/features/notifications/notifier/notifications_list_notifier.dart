import 'package:hiddify/features/notifications/data/notification_data_providers.dart';
import 'package:hiddify/features/notifications/data/notification_data_source.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notifications_list_notifier.g.dart';

/// All notifications, newest first — backs the inbox screen.
@riverpod
Stream<List<AppNotification>> notificationsList(Ref ref) {
  return ref
      .watch(notificationDataSourceProvider)
      .watchAll()
      .map((rows) => rows.map((row) => row.toEntity()).toList());
}

/// Undismissed notifications, newest first — backs the connection-page banner.
@riverpod
Stream<List<AppNotification>> activeNotifications(Ref ref) {
  return ref
      .watch(notificationDataSourceProvider)
      .watchActive()
      .map((rows) => rows.map((row) => row.toEntity()).toList());
}
