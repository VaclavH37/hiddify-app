import 'package:drift/drift.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';

part 'notification_data_source.g.dart';

abstract interface class NotificationDataSource {
  /// All notifications, newest first (the inbox).
  Stream<List<AppNotificationEntry>> watchAll();

  /// Undismissed notifications, newest first (the connection-page banner).
  Stream<List<AppNotificationEntry>> watchActive();

  /// Count of unseen notifications (the bell badge).
  Stream<int> watchUnreadCount();

  Future<void> insert(AppNotificationsCompanion entry);
  Future<void> markDismissed(String id);
  Future<void> markAllSeen();
  Future<void> deleteAll();
}

@DriftAccessor(tables: [AppNotifications])
class NotificationDao extends DatabaseAccessor<Db> with _$NotificationDaoMixin implements NotificationDataSource {
  NotificationDao(super.db);

  @override
  Stream<List<AppNotificationEntry>> watchAll() {
    return (select(appNotifications)
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)]))
        .watch();
  }

  @override
  Stream<List<AppNotificationEntry>> watchActive() {
    return (select(appNotifications)
          ..where((tbl) => tbl.dismissed.equals(false))
          ..orderBy([(tbl) => OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.desc)]))
        .watch();
  }

  @override
  Stream<int> watchUnreadCount() {
    final count = appNotifications.id.count();
    return (selectOnly(appNotifications)
          ..addColumns([count])
          ..where(appNotifications.seen.equals(false)))
        .map((row) => row.read(count)!)
        .watchSingle()
        .distinct();
  }

  @override
  Future<void> insert(AppNotificationsCompanion entry) async {
    await into(appNotifications).insert(entry);
  }

  @override
  Future<void> markDismissed(String id) async {
    await (update(appNotifications)..where((tbl) => tbl.id.equals(id))).write(
      const AppNotificationsCompanion(dismissed: Value(true)),
    );
  }

  @override
  Future<void> markAllSeen() async {
    await update(appNotifications).write(const AppNotificationsCompanion(seen: Value(true)));
  }

  @override
  Future<void> deleteAll() async {
    await delete(appNotifications).go();
  }
}

extension AppNotificationEntryMapper on AppNotificationEntry {
  AppNotification toEntity() => AppNotification(
    id: id,
    kind: kind,
    thresholdValue: thresholdValue,
    createdAt: createdAt,
    seen: seen,
    dismissed: dismissed,
  );
}
