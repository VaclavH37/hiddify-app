import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Migration v8 forgets "Auto rotate" (the core's removed `balance` group) in
/// the three records the app keeps about the exit location.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const locationKey = 'selected_location';
  const pendingKey = 'selected_location_pending';
  const snapshotKey = 'proxy_group_snapshot';

  Map<String, Object?> item(String tag, {bool group = false}) => {
    't': tag,
    'd': tag,
    'y': group ? 'urltest' : 'vless',
    'g': group,
    'sd': '',
    'c': 'JP',
  };

  String snapshot(String selected, List<Map<String, Object?>> items) =>
      jsonEncode({'g': 'select', 's': selected, 'i': items});

  Future<SharedPreferences> migrated(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    await PreferencesVersion8Migration(prefs).migrate();
    return prefs;
  }

  group('selected_location', () {
    test('an Auto rotate record is dropped', () async {
      final prefs = await migrated({locationKey: '{"n":"Tokyo, JP","c":"JP","m":"rotate"}'});
      expect(prefs.getString(locationKey), isNull);
    });

    test('Fastest and chosen records are kept as they are', () async {
      for (final raw in [
        '{"n":"Tokyo, JP","c":"JP","m":"fastest"}',
        '{"n":"Seoul, KR","c":"KR","m":"chosen"}',
        '{"n":"Tokyo, JP","c":"JP","a":true}',
      ]) {
        final prefs = await migrated({locationKey: raw});
        expect(prefs.getString(locationKey), raw);
      }
    });
  });

  group('selected_location_pending', () {
    test('a pending Auto rotate pick is dropped', () async {
      final prefs = await migrated({pendingKey: '{"g":"select","o":"balance"}'});
      expect(prefs.getString(pendingKey), isNull);
    });

    test('any other pending pick is kept', () async {
      const raw = '{"g":"select","o":"EXIT-Tokyo"}';
      final prefs = await migrated({pendingKey: raw});
      expect(prefs.getString(pendingKey), raw);
    });
  });

  group('proxy_group_snapshot', () {
    test('the Auto rotate row is removed and its selection moves to Fastest', () async {
      final prefs = await migrated({
        snapshotKey: snapshot('balance', [
          item('lowest', group: true),
          item('balance', group: true),
          item('EXIT-Tokyo'),
        ]),
      });
      final decoded = jsonDecode(prefs.getString(snapshotKey)!) as Map<String, dynamic>;
      expect(decoded['s'], 'lowest');
      expect([for (final i in decoded['i'] as List) (i as Map)['t']], ['lowest', 'EXIT-Tokyo']);
    });

    test('an unselected Auto rotate row is removed and the selection kept', () async {
      final prefs = await migrated({
        snapshotKey: snapshot('EXIT-Tokyo', [
          item('lowest', group: true),
          item('balance', group: true),
          item('EXIT-Tokyo'),
        ]),
      });
      final decoded = jsonDecode(prefs.getString(snapshotKey)!) as Map<String, dynamic>;
      expect(decoded['s'], 'EXIT-Tokyo');
      expect([for (final i in decoded['i'] as List) (i as Map)['t']], ['lowest', 'EXIT-Tokyo']);
    });

    test('with no Fastest row to move to, the selection is cleared', () async {
      final prefs = await migrated({
        snapshotKey: snapshot('balance', [item('balance', group: true), item('EXIT-Tokyo')]),
      });
      final decoded = jsonDecode(prefs.getString(snapshotKey)!) as Map<String, dynamic>;
      expect(decoded['s'], '');
    });

    test('a snapshot left with no rows is removed', () async {
      final prefs = await migrated({
        snapshotKey: snapshot('balance', [item('balance', group: true)]),
      });
      expect(prefs.getString(snapshotKey), isNull);
    });

    test('a snapshot without Auto rotate is left byte for byte', () async {
      final raw = snapshot('lowest', [item('lowest', group: true), item('EXIT-Tokyo')]);
      final prefs = await migrated({snapshotKey: raw});
      expect(prefs.getString(snapshotKey), raw);
    });
  });

  test('records that do not parse are left alone', () async {
    final prefs = await migrated({locationKey: 'garbage', pendingKey: '[1,2]', snapshotKey: '{"i":"not a list"}'});
    expect(prefs.getString(locationKey), 'garbage');
    expect(prefs.getString(pendingKey), '[1,2]');
    expect(prefs.getString(snapshotKey), '{"i":"not a list"}');
  });

  test('nothing stored: nothing written', () async {
    final prefs = await migrated({});
    expect(prefs.getKeys(), isEmpty);
  });

  test('running it twice changes nothing more', () async {
    final prefs = await migrated({
      locationKey: '{"n":"Tokyo, JP","c":"JP","m":"rotate"}',
      snapshotKey: snapshot('balance', [item('lowest', group: true), item('balance', group: true)]),
    });
    final once = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    await PreferencesVersion8Migration(prefs).migrate();
    expect({for (final k in prefs.getKeys()) k: prefs.get(k)}, once);
  });

  test('an install on v7 reaches v8 through PreferencesMigration', () async {
    SharedPreferences.setMockInitialValues({
      PreferencesMigration.versionKey: 7,
      locationKey: '{"n":"Tokyo, JP","c":"JP","m":"rotate"}',
    });
    final prefs = await SharedPreferences.getInstance();
    await PreferencesMigration(sharedPreferences: prefs).migrate();
    expect(prefs.getInt(PreferencesMigration.versionKey), 8);
    expect(prefs.getString(locationKey), isNull);
  });
}
