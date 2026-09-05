import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:hiddify/core/db/converters/duration_converter.dart';
import 'package:hiddify/core/db/db.steps.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/features/notifications/model/app_notification.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/utils/custom_loggers.dart';

part 'db.g.dart';

@DriftDatabase(tables: [ProfileEntries, AppNotifications])
class Db extends _$Db with InfraLogger {
  Db([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 11;

  static QueryExecutor _openConnection() {
    return LazyDatabase(
      () => driftDatabase(
        name: "db",
        native: const DriftNativeOptions(databaseDirectory: AppDirectories.getDatabaseDirectory),
        web: DriftWebOptions(sqlite3Wasm: Uri.parse('sqlite3.wasm'), driftWorker: Uri.parse('drift_worker.js')),
      ),
    );
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: stepByStep(
        from1To2: (m, schema) async {
          await m.alterTable(
            // TableMigration is the only way to transform a column during an
            // alterTable, and Drift has shipped it as experimental for years
            // with no stable successor. The ignore must sit on the line
            // immediately above the expression, hence the split from the prose.
            // ignore: experimental_member_use
            TableMigration(
              schema.profileEntries,
              columnTransformer: {schema.profileEntries.type: const Constant<String>("remote")},
              newColumns: [schema.profileEntries.type],
            ),
          );
        },
        from2To3: (m, schema) async {
          await m.createTable(schema.geoAssetEntries);
        },
        from3To4: (m, schema) async {
          final testUrlExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.testUrl.name,
          );
          if (!testUrlExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.testUrl);
          }
        },
        from4To5: (m, schema) async {
          await m.deleteTable('geo_asset_entries');
          await m.renameColumn(schema.profileEntries, 'test_url', schema.profileEntries.profileOverride);

          final userOverrideExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.userOverride.name,
          );
          if (!userOverrideExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.userOverride);
          }

          final populatedHeadersExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.populatedHeaders.name,
          );
          if (!populatedHeadersExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.populatedHeaders);
          }

          await m.createTable(schema.appProxyEntries);
        },
        from5To6: (m, schema) async {
          final sourceTokenExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.sourceToken.name,
          );
          if (!sourceTokenExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.sourceToken);
          }
        },
        from6To7: (m, schema) async {
          final fallbackUrlExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.fallbackUrl.name,
          );
          if (!fallbackUrlExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.fallbackUrl);
          }
          final fallbackTokenExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.fallbackSourceToken.name,
          );
          if (!fallbackTokenExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.fallbackSourceToken);
          }
        },
        from7To8: (m, schema) async {
          // Per-app proxy feature removed (Play Store Finding #1) — drop its
          // now-unused table. Created in from4To5; harmless if already absent.
          await m.deleteTable('app_proxy_entries');
        },
        from8To9: (m, schema) async {
          // `subscription-refill-date` quota-reset column.
          final refillExists = await _columnExists(
            schema.profileEntries.actualTableName,
            schema.profileEntries.refillDate.name,
          );
          if (!refillExists) {
            await m.addColumn(schema.profileEntries, schema.profileEntries.refillDate);
          }
        },
        from9To10: (m, schema) async {
          // In-app notifications inbox (quota + expiry alerts). New table.
          await m.createTable(schema.appNotifications);
        },
        from10To11: (m, schema) async {
          // The quota notification kinds are gone. `kind` is a textEnum, which
          // drift resolves with `values.byName` — that THROWS on a name the
          // enum no longer declares, so a single leftover row would break the
          // whole inbox rather than degrade. Delete them here.
          //
          // Raw SQL on purpose: the generated schema for v11 no longer has
          // these enum values to name, and the rows are transient inbox
          // entries, so there is nothing to preserve or translate.
          await customStatement(
            "DELETE FROM app_notifications WHERE kind IN ('quota80', 'quota90', 'quota100')",
          );
        },
      ),
    );
  }

  Future<bool> _columnExists(String table, String column) async {
    final result = await customSelect('PRAGMA table_info($table);').get();
    return result.any((row) => row.data['name'] == column);
  }
}

@DataClassName('ProfileEntry')
class ProfileEntries extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<ProfileType>()();
  BoolColumn get active => boolean()();
  TextColumn get name => text().withLength(min: 1)();
  TextColumn get url => text().nullable()();
  DateTimeColumn get lastUpdate => dateTime()();
  IntColumn get updateInterval => integer().nullable().map(DurationTypeConverter())();
  IntColumn get upload => integer().nullable()();
  IntColumn get download => integer().nullable()();
  IntColumn get total => integer().nullable()();
  DateTimeColumn get expire => dateTime().nullable()();
  // Unix `subscription-refill-date` header → when the traffic quota next
  // resets. Nullable: optional header and pre-v9 rows.
  DateTimeColumn get refillDate => dateTime().nullable()();
  TextColumn get webPageUrl => text().nullable()();
  TextColumn get supportUrl => text().nullable()();
  TextColumn get populatedHeaders => text().nullable()();
  TextColumn get profileOverride => text().nullable()();
  TextColumn get userOverride => text().nullable()();
  // Original `rayn://import/<token>` string captured at import time so the
  // user can copy their token before logging out. Nullable for upgrade rows.
  TextColumn get sourceToken => text().nullable()();
  // Decrypted https URL parsed from the optional `fallback-url` response
  // header. Used by the parser failover path when the primary URL is
  // unreachable. Independent channel from `url`/`sourceToken` — the
  // primary is never overwritten.
  TextColumn get fallbackUrl => text().nullable()();
  // Raw `rayn://import/<token>` string the fallback header arrived as,
  // persisted for parity with `sourceToken`. Decryption-as-validation
  // already happened, so this is opaque ciphertext at rest.
  TextColumn get fallbackSourceToken => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// In-app notifications shown as a swipe-away banner on the connection page and
/// kept in the bell inbox. Rows store a semantic [kind] + numeric
/// [thresholdValue] (never rendered strings) so copy stays localizable.
@DataClassName('AppNotificationEntry')
class AppNotifications extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<NotificationKind>()();
  IntColumn get thresholdValue => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get seen => boolean().withDefault(const Constant(false))();
  BoolColumn get dismissed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
