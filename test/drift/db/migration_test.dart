// dart format width=80
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'generated/schema.dart';

import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;
import 'generated/schema_v6.dart' as v6;
import 'generated/schema_v7.dart' as v7;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = Db(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  group('_columnExists-backed migrations', () {
    test('migration from v3 to v4 adds test_url when missing', () async {
      final schema = await verifier.schemaAt(3);
      addTearDown(() => schema.rawDatabase.dispose());

      final oldDb = v3.DatabaseAtV3(schema.newConnection());
      final oldColumns = await oldDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();

      expect(
        oldColumns.where((row) => row.data['name'] == 'test_url'),
        isEmpty,
      );
      await oldDb.close();

      final migratedDb = Db(schema.newConnection());
      await verifier.migrateAndValidate(migratedDb, 4);
      await migratedDb.close();

      final newDb = v4.DatabaseAtV4(schema.newConnection());
      final newColumns = await newDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();
      expect(
        newColumns.where((row) => row.data['name'] == 'test_url'),
        hasLength(1),
      );
      await newDb.close();
    });

    test(
      'migration from v3 to v4 skips adding test_url when it already exists',
      () async {
        final schema = await verifier.schemaAt(3);
        addTearDown(() => schema.rawDatabase.dispose());

        schema.rawDatabase.execute(
          'ALTER TABLE profile_entries ADD COLUMN test_url TEXT NULL;',
        );

        final migratedDb = Db(schema.newConnection());
        await verifier.migrateAndValidate(migratedDb, 4);
        await migratedDb.close();

        final newDb = v4.DatabaseAtV4(schema.newConnection());
        final newColumns = await newDb
            .customSelect('PRAGMA table_info(profile_entries);')
            .get();
        expect(
          newColumns.where((row) => row.data['name'] == 'test_url'),
          hasLength(1),
        );
        await newDb.close();
      },
    );

    test('migration from v5 to v6 adds source_token when missing', () async {
      final schema = await verifier.schemaAt(5);
      addTearDown(() => schema.rawDatabase.dispose());

      final oldDb = v5.DatabaseAtV5(schema.newConnection());
      final oldColumns = await oldDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();
      expect(
        oldColumns.where((row) => row.data['name'] == 'source_token'),
        isEmpty,
      );
      await oldDb.close();

      final migratedDb = Db(schema.newConnection());
      await verifier.migrateAndValidate(migratedDb, 6);
      await migratedDb.close();

      final newDb = v6.DatabaseAtV6(schema.newConnection());
      final newColumns = await newDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();
      expect(
        newColumns.where((row) => row.data['name'] == 'source_token'),
        hasLength(1),
      );
      await newDb.close();
    });

    test(
      'migration from v5 to v6 skips adding source_token when it already exists',
      () async {
        final schema = await verifier.schemaAt(5);
        addTearDown(() => schema.rawDatabase.dispose());

        schema.rawDatabase.execute(
          'ALTER TABLE profile_entries ADD COLUMN source_token TEXT NULL;',
        );

        final migratedDb = Db(schema.newConnection());
        await verifier.migrateAndValidate(migratedDb, 6);
        await migratedDb.close();

        final newDb = v6.DatabaseAtV6(schema.newConnection());
        final newColumns = await newDb
            .customSelect('PRAGMA table_info(profile_entries);')
            .get();
        expect(
          newColumns.where((row) => row.data['name'] == 'source_token'),
          hasLength(1),
        );
        await newDb.close();
      },
    );

    test(
      'migration from v6 to v7 adds fallback_url and fallback_source_token when missing',
      () async {
        final schema = await verifier.schemaAt(6);
        addTearDown(() => schema.rawDatabase.dispose());

        final oldDb = v6.DatabaseAtV6(schema.newConnection());
        final oldColumns = await oldDb
            .customSelect('PRAGMA table_info(profile_entries);')
            .get();
        expect(
          oldColumns.where((row) => row.data['name'] == 'fallback_url'),
          isEmpty,
        );
        expect(
          oldColumns.where((row) => row.data['name'] == 'fallback_source_token'),
          isEmpty,
        );
        await oldDb.close();

        final migratedDb = Db(schema.newConnection());
        await verifier.migrateAndValidate(migratedDb, 7);
        await migratedDb.close();

        final newDb = v7.DatabaseAtV7(schema.newConnection());
        final newColumns = await newDb
            .customSelect('PRAGMA table_info(profile_entries);')
            .get();
        expect(
          newColumns.where((row) => row.data['name'] == 'fallback_url'),
          hasLength(1),
        );
        expect(
          newColumns.where((row) => row.data['name'] == 'fallback_source_token'),
          hasLength(1),
        );
        await newDb.close();
      },
    );

    test(
      'migration from v6 to v7 skips adding fallback columns when they already exist',
      () async {
        final schema = await verifier.schemaAt(6);
        addTearDown(() => schema.rawDatabase.dispose());

        schema.rawDatabase.execute(
          'ALTER TABLE profile_entries ADD COLUMN fallback_url TEXT NULL;',
        );
        schema.rawDatabase.execute(
          'ALTER TABLE profile_entries ADD COLUMN fallback_source_token TEXT NULL;',
        );

        final migratedDb = Db(schema.newConnection());
        await verifier.migrateAndValidate(migratedDb, 7);
        await migratedDb.close();

        final newDb = v7.DatabaseAtV7(schema.newConnection());
        final newColumns = await newDb
            .customSelect('PRAGMA table_info(profile_entries);')
            .get();
        expect(
          newColumns.where((row) => row.data['name'] == 'fallback_url'),
          hasLength(1),
        );
        expect(
          newColumns.where((row) => row.data['name'] == 'fallback_source_token'),
          hasLength(1),
        );
        await newDb.close();
      },
    );

    test('migration from v8 to v9 adds refill_date when missing', () async {
      final schema = await verifier.schemaAt(8);
      addTearDown(() => schema.rawDatabase.dispose());

      final oldDb = v8.DatabaseAtV8(schema.newConnection());
      final oldColumns = await oldDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();
      expect(
        oldColumns.where((row) => row.data['name'] == 'refill_date'),
        isEmpty,
      );
      await oldDb.close();

      final migratedDb = Db(schema.newConnection());
      await verifier.migrateAndValidate(migratedDb, 9);
      await migratedDb.close();

      final newDb = v9.DatabaseAtV9(schema.newConnection());
      final newColumns = await newDb
          .customSelect('PRAGMA table_info(profile_entries);')
          .get();
      expect(
        newColumns.where((row) => row.data['name'] == 'refill_date'),
        hasLength(1),
      );
      await newDb.close();
    });

    test(
      'migration from v8 to v9 skips adding refill_date when it already exists',
      () async {
        final schema = await verifier.schemaAt(8);
        addTearDown(() => schema.rawDatabase.dispose());

        schema.rawDatabase.execute(
          'ALTER TABLE profile_entries ADD COLUMN refill_date TEXT NULL;',
        );

        final migratedDb = Db(schema.newConnection());
        await verifier.migrateAndValidate(migratedDb, 9);
        await migratedDb.close();

        final newDb = v9.DatabaseAtV9(schema.newConnection());
        final newColumns = await newDb
            .customSelect('PRAGMA table_info(profile_entries);')
            .get();
        expect(
          newColumns.where((row) => row.data['name'] == 'refill_date'),
          hasLength(1),
        );
        await newDb.close();
      },
    );
  });
}
