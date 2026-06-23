import 'package:hiddify/features/notifications/data/notification_data_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'unread_count_notifier.g.dart';

/// Count of unseen notifications — drives the bell badge.
@riverpod
Stream<int> unreadNotificationsCount(Ref ref) {
  return ref.watch(notificationDataSourceProvider).watchUnreadCount();
}
