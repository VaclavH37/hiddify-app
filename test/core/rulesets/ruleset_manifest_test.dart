import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:path/path.dart' as p;

/// The manifest is what orders a bundled rule-set against a downloaded one, so
/// its version has to read the same on every device, and the committed bundle
/// has to describe the files actually committed beside it.
void main() {
  group('parseRulesetVersion', () {
    test('reads a UTC timestamp', () {
      expect(parseRulesetVersion('2026-09-20T13:54:30Z'), DateTime.utc(2026, 9, 20, 13, 54, 30));
    });

    test('reads fractional seconds', () {
      expect(parseRulesetVersion('2026-09-20T13:54:30.250Z'), DateTime.utc(2026, 9, 20, 13, 54, 30, 250));
    });

    // Every MANIFEST written before the mirror carries a bare date.
    test('reads a bare date as midnight UTC', () {
      expect(parseRulesetVersion('2026-09-20'), DateTime.utc(2026, 9, 20));
    });

    test('orders the old date form before a same-day timestamp', () {
      expect(parseRulesetVersion('2026-09-20')!.isBefore(parseRulesetVersion('2026-09-20T13:54:30Z')!), isTrue);
    });

    // DateTime.parse would read these in the device's local time, so two
    // devices could order the same pair of manifests differently.
    test('refuses a timestamp without a zone, or with an offset', () {
      expect(parseRulesetVersion('2026-09-20T13:54:30'), isNull);
      expect(parseRulesetVersion('2026-09-20T13:54:30+08:00'), isNull);
    });

    test('refuses a date that does not exist rather than rolling it over', () {
      expect(parseRulesetVersion('2026-02-30'), isNull);
      expect(parseRulesetVersion('2026-13-01'), isNull);
    });

    test('refuses anything else', () {
      for (final bad in ['', 'latest', '20260920', '2026-9-20', ' 2026-09-20', '2026-09-20T13:54Z']) {
        expect(parseRulesetVersion(bad), isNull, reason: bad);
      }
    });
  });

  group('RulesetManifest', () {
    const file = {'name': 'direct-private.srs', 'sha256': 'ab', 'size': 1};

    test('reads schema, version and fetched_at', () {
      final manifest = RulesetManifest.fromJson(const {
        'schema': 2,
        'version': '2026-10-05T18:30:00Z',
        'fetched_at': '2026-10-05T18:29:12Z',
        'files': [file],
      });
      expect(manifest.schema, 2);
      expect(manifest.versionTime, DateTime.utc(2026, 10, 5, 18, 30));
      expect(manifest.fetchedAt, '2026-10-05T18:29:12Z');
      expect(manifest.fileNames, {'direct-private.srs'});
    });

    // An install upgraded from a build before the mirror still has its old
    // MANIFEST on disk. It describes the schema-1 file set.
    test('a manifest without a schema is schema 1', () {
      final manifest = RulesetManifest.fromJson(const {
        'version': '2026-09-20',
        'files': [file],
      });
      expect(manifest.schema, 1);
      expect(manifest.fetchedAt, isNull);
      expect(manifest.versionTime, DateTime.utc(2026, 9, 20));
    });

    test('an unreadable version has no time', () {
      final manifest = RulesetManifest.fromJson(const {
        'version': 'latest',
        'files': [file],
      });
      expect(manifest.versionTime, isNull);
    });
  });

  // The committed bundle against the files committed beside it. A forgotten
  // regen after `make fetch-rulesets` would otherwise ship a MANIFEST whose
  // digests fail on every launch, so every launch re-extracts and nothing
  // ever looks wrong.
  group('the bundled MANIFEST', () {
    final dir = Directory(p.join('assets', 'rulesets'));
    final manifest = RulesetManifest.fromJson(
      jsonDecode(File(p.join(dir.path, 'MANIFEST')).readAsStringSync()) as Map<String, dynamic>,
    );

    test('is the schema this build expects', () {
      expect(manifest.schema, kRulesetSchema);
    });

    test('has a timestamp version equal to its fetch time', () {
      expect(manifest.versionTime, isNotNull);
      expect(manifest.version, manifest.fetchedAt);
    });

    test('lists every .srs file beside it, and nothing else', () {
      final onDisk = dir
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((name) => name.endsWith('.srs'))
          .toSet();
      expect(manifest.fileNames, onDisk);
    });

    test("records each file's real digest and size", () {
      for (final entry in manifest.files) {
        final bytes = File(p.join(dir.path, entry.name)).readAsBytesSync();
        expect(sha256.convert(bytes).toString(), entry.sha256, reason: entry.name);
        expect(bytes.length, entry.size, reason: entry.name);
      }
    });
  });
}
