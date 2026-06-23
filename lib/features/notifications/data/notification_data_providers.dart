import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/notifications/data/notification_data_source.dart';
import 'package:hiddify/features/notifications/data/notification_dedup_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'notification_data_providers.g.dart';

@Riverpod(keepAlive: true)
NotificationDataSource notificationDataSource(Ref ref) {
  return NotificationDao(ref.watch(dbProvider));
}

@Riverpod(keepAlive: true)
NotificationDedupStore notificationDedupStore(Ref ref) {
  return NotificationDedupStore(ref.watch(sharedPreferencesProvider).requireValue);
}
