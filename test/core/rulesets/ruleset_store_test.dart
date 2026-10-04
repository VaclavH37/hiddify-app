import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:hiddify/core/rulesets/ruleset_store.dart';
import 'package:path/path.dart' as p;

/// The rule-sets on disk decide whether the core starts at all: a missing or
/// corrupt file is fatal to the next start. These cover the three ways files
/// get there (the bundle at launch, a download from the mirror, a download a
/// Windows rename refused and staged) and the rule that picks between them.
void main() {
  const bundleVersion = '2026-09-20T13:54:30Z';
  const newer = '2026-10-05T18:30:00Z';
  const newest = '2026-10-12T18:30:00Z';

  final bundleFiles = <String, List<int>>{
    'direct-private.srs': [1, 1, 1],
    'direct-regional-sites.srs': [2, 2, 2, 2],
    'block-ads.srs': [3, 3, 3, 3, 3],
  };

  String digest(List<int> bytes) => sha256.convert(bytes).toString();

  RulesetManifest manifestOf(String version, Map<String, List<int>> files, {int schema = 1}) => RulesetManifest(
    schema: schema,
    version: version,
    fetchedAt: version,
    files: [
      for (final MapEntry(key: name, value: bytes) in files.entries)
        RulesetManifestFile(name: name, sha256: digest(bytes), size: bytes.length),
    ],
  );

  late Directory work;
  late _FakeBundle bundle;

  RulesetStore store({RulesetRename? rename}) =>
      RulesetStore(work, bundle: bundle, renameRetries: const [], rename: rename);

  File onDisk(String name) => File(p.join(work.path, 'rulesets', name));

  Future<RulesetManifest> installedManifest() async =>
      RulesetManifest.fromJson(jsonDecode(await onDisk('MANIFEST').readAsString()) as Map<String, dynamic>);

  Future<Map<String, List<int>>> filesOnDisk() async => {
    for (final name in bundleFiles.keys) name: await onDisk(name).readAsBytes(),
  };

  /// The bundle with block-ads changed: what a mirror publish usually is.
  final downloaded = {
    ...bundleFiles,
    'block-ads.srs': <int>[9, 9, 9, 9, 9, 9],
  };

  setUp(() async {
    work = await Directory.systemTemp.createTemp('ruleset_store_test');
    bundle = _FakeBundle(manifestOf(bundleVersion, bundleFiles), bundleFiles);
  });

  tearDown(() async {
    if (work.existsSync()) await work.delete(recursive: true);
  });

  group('chooseInstalled', () {
    final bundled = manifestOf(bundleVersion, bundleFiles);

    RulesetChoice choose(RulesetManifest? installed, {bool intact = true, Set<String> rejected = const {}}) =>
        chooseInstalled(bundled: bundled, installed: installed, installedIntact: intact, rejected: rejected).choice;

    test('extracts the bundle when nothing is installed', () {
      expect(choose(null), RulesetChoice.extractBundled);
    });

    test('keeps the bundle already on disk', () {
      expect(choose(bundled), RulesetChoice.keepInstalled);
    });

    test('keeps a download newer than the bundle', () {
      final result = chooseInstalled(
        bundled: bundled,
        installed: manifestOf(newer, downloaded),
        installedIntact: true,
        rejected: const {},
      );
      expect(result.choice, RulesetChoice.keepInstalled);
      expect(result.reason, contains('downloaded'));
    });

    // An app update whose bundle is fresher than the last download.
    test('replaces a download older than the bundle', () {
      expect(choose(manifestOf('2026-09-01T00:00:00Z', downloaded)), RulesetChoice.extractBundled);
    });

    // Every install upgraded from a build before the mirror.
    test('replaces a same-day MANIFEST in the old date-only form', () {
      expect(choose(manifestOf('2026-09-20', bundleFiles)), RulesetChoice.extractBundled);
    });

    test('replaces a set for another schema', () {
      expect(choose(manifestOf(newer, downloaded, schema: 2)), RulesetChoice.extractBundled);
    });

    test('replaces a set naming other files', () {
      expect(
        choose(
          manifestOf(newer, {
            ...downloaded,
            'extra.srs': <int>[7],
          }),
        ),
        RulesetChoice.extractBundled,
      );
      expect(
        choose(
          manifestOf(newer, {
            'direct-private.srs': <int>[1, 1, 1],
          }),
        ),
        RulesetChoice.extractBundled,
      );
    });

    test('replaces a set with a file failing its digest', () {
      expect(choose(manifestOf(newer, downloaded), intact: false), RulesetChoice.extractBundled);
    });

    test('replaces a rejected version', () {
      expect(choose(manifestOf(newer, downloaded), rejected: {newer}), RulesetChoice.extractBundled);
    });

    test('replaces an unreadable version', () {
      expect(choose(manifestOf('latest', downloaded)), RulesetChoice.extractBundled);
    });
  });

  group('ensureInstalled', () {
    test('extracts the bundle on first launch, then leaves it', () async {
      expect(await store().ensureInstalled(), isTrue);
      expect(await filesOnDisk(), bundleFiles);
      expect(await onDisk('MANIFEST').readAsString(), bundle.json);

      expect(await store().ensureInstalled(), isFalse);
    });

    test('restores a file that fails its digest', () async {
      await store().ensureInstalled();
      await onDisk('block-ads.srs').writeAsBytes([3, 3], flush: true);

      expect(await store().ensureInstalled(), isTrue);
      expect(await onDisk('block-ads.srs').readAsBytes(), bundleFiles['block-ads.srs']);
    });

    test('removes rule-sets the bundle no longer lists, and leftover temp files', () async {
      await store().ensureInstalled();
      await onDisk('fakeip-remote-sites.srs').writeAsBytes([5], flush: true);
      await onDisk('block-ads.srs.tmp').writeAsBytes([5], flush: true);
      await onDisk('block-ads.srs').writeAsBytes([3], flush: true); // forces an extraction

      await store().ensureInstalled();
      expect(onDisk('fakeip-remote-sites.srs').existsSync(), isFalse);
      expect(onDisk('block-ads.srs.tmp').existsSync(), isFalse);
    });

    test('keeps a newer download across launches', () async {
      await store().ensureInstalled();
      await store().installDownloaded(manifestOf(newer, downloaded), {'block-ads.srs': downloaded['block-ads.srs']!});

      expect(await store().ensureInstalled(), isFalse);
      expect(await filesOnDisk(), downloaded);
    });

    test('an app update with a fresher bundle replaces the download and clears pending', () async {
      await store().ensureInstalled();
      await store().installDownloaded(manifestOf(newer, downloaded), {'block-ads.srs': downloaded['block-ads.srs']!});

      final freshFiles = {
        ...bundleFiles,
        'direct-private.srs': <int>[4, 4],
      };
      bundle = _FakeBundle(manifestOf(newest, freshFiles), freshFiles);
      expect(await store().ensureInstalled(), isTrue);
      expect(await filesOnDisk(), freshFiles);
      expect((await store().readState()).pending, isNull);
    });

    // A crash between renaming the files and writing the MANIFEST leaves new
    // files under the old MANIFEST. The next launch must not trust them.
    test('restores the bundle when files disagree with their MANIFEST', () async {
      await store().ensureInstalled();
      await onDisk('block-ads.srs').writeAsBytes(downloaded['block-ads.srs']!, flush: true);

      expect(await store().ensureInstalled(), isTrue);
      expect(await filesOnDisk(), bundleFiles);
    });
  });

  group('installDownloaded', () {
    setUp(() => store().ensureInstalled());

    test('replaces the changed files, then the MANIFEST, and marks the version pending', () async {
      final result = await store().installDownloaded(manifestOf(newer, downloaded), {
        'block-ads.srs': downloaded['block-ads.srs']!,
      });

      expect(result.status, RulesetInstallStatus.installed);
      expect(await filesOnDisk(), downloaded);
      expect((await installedManifest()).version, newer);
      expect((await store().readState()).pending, newer);
      expect(Directory(p.join(work.path, 'rulesets')).listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    group('refuses, changing nothing,', () {
      Future<void> expectRefused(RulesetManifest manifest, Map<String, List<int>> changed) async {
        final result = await store().installDownloaded(manifest, changed);
        expect(result.status, RulesetInstallStatus.refused, reason: result.detail);
        expect(await filesOnDisk(), bundleFiles);
        expect((await installedManifest()).version, bundleVersion);
        expect((await store().readState()).pending, isNull);
      }

      final changedAds = {
        'block-ads.srs': <int>[9, 9, 9, 9, 9, 9],
      };

      test('a set for another schema', () async {
        await expectRefused(manifestOf(newer, downloaded, schema: 2), changedAds);
      });

      test('a set naming other files', () async {
        await expectRefused(
          manifestOf(newer, {
            ...downloaded,
            'extra.srs': <int>[7],
          }),
          changedAds,
        );
      });

      test('a set that is not newer than the installed one', () async {
        await expectRefused(manifestOf(bundleVersion, downloaded), changedAds);
        await expectRefused(manifestOf('2026-09-01T00:00:00Z', downloaded), changedAds);
      });

      test('a set with an unreadable version', () async {
        await expectRefused(manifestOf('latest', downloaded), changedAds);
      });

      test('bytes that do not match the manifest', () async {
        await expectRefused(manifestOf(newer, downloaded), {
          'block-ads.srs': <int>[9, 9, 9],
        });
      });

      test('a file it says is unchanged but whose copy on disk differs', () async {
        final alsoChanged = {
          ...downloaded,
          'direct-private.srs': <int>[8, 8],
        };
        await expectRefused(manifestOf(newer, alsoChanged), changedAds);
      });

      test('bytes for a file the manifest does not list', () async {
        await expectRefused(manifestOf(newer, downloaded), {
          ...changedAds,
          'extra.srs': <int>[7],
        });
      });

      test('a version rejected before', () async {
        await store().installDownloaded(manifestOf(newer, downloaded), changedAds);
        await store().revertToBundled(reject: newer);
        await expectRefused(manifestOf(newer, downloaded), changedAds);
      });
    });

    // Windows: the core holds a loaded rule-set open without delete sharing.
    test('stages the download when a rename is refused, and installs it at the next launch', () async {
      Future<void> refuseAds(File from, String to) async {
        if (p.basename(to) == 'block-ads.srs') throw FileSystemException('in use', to);
        await from.rename(to);
      }

      final result = await store(
        rename: refuseAds,
      ).installDownloaded(manifestOf(newer, downloaded), {'block-ads.srs': downloaded['block-ads.srs']!});
      expect(result.status, RulesetInstallStatus.staged);
      expect(await filesOnDisk(), bundleFiles);
      expect((await installedManifest()).version, bundleVersion);
      final staged = Directory(p.join(work.path, 'rulesets-staged'));
      expect(File(p.join(staged.path, 'MANIFEST')).existsSync(), isTrue);
      expect(File(p.join(staged.path, 'block-ads.srs')).readAsBytesSync(), downloaded['block-ads.srs']);

      expect(await store().ensureInstalled(), isFalse);
      expect(await filesOnDisk(), downloaded);
      expect((await installedManifest()).version, newer);
      expect((await store().readState()).pending, newer);
      expect(staged.existsSync(), isFalse);
    });

    test('discards a staged download that is no longer newer than the installed set', () async {
      Future<void> refuseAll(File from, String to) async => throw FileSystemException('in use', to);
      await store(
        rename: refuseAll,
      ).installDownloaded(manifestOf(newer, downloaded), {'block-ads.srs': downloaded['block-ads.srs']!});

      final freshFiles = {
        ...bundleFiles,
        'direct-private.srs': <int>[4, 4],
      };
      bundle = _FakeBundle(manifestOf(newest, freshFiles), freshFiles);
      await store().ensureInstalled();

      expect(await filesOnDisk(), freshFiles);
      expect(Directory(p.join(work.path, 'rulesets-staged')).existsSync(), isFalse);
    });
  });

  group('state', () {
    setUp(() => store().ensureInstalled());

    test('revertToBundled puts the bundle back, rejects the version and clears pending', () async {
      await store().installDownloaded(manifestOf(newer, downloaded), {'block-ads.srs': downloaded['block-ads.srs']!});
      await store().revertToBundled(reject: newer);

      expect(await filesOnDisk(), bundleFiles);
      final state = await store().readState();
      expect(state.pending, isNull);
      expect(state.rejected, [newer]);
    });

    test('confirmPending clears pending and keeps the set', () async {
      await store().installDownloaded(manifestOf(newer, downloaded), {'block-ads.srs': downloaded['block-ads.srs']!});
      await store().confirmPending();

      expect((await store().readState()).pending, isNull);
      expect(await filesOnDisk(), downloaded);
    });

    test('recordCheck remembers when the mirror was last asked', () async {
      await store().recordCheck(DateTime.utc(2026, 10, 5, 9));
      expect((await store().readState()).lastCheck, DateTime.utc(2026, 10, 5, 9));
    });

    test('remembers at most five rejected versions, newest last', () {
      var state = const RulesetState();
      for (var day = 1; day <= 7; day++) {
        state = state.withRejected('2026-10-0${day}T00:00:00Z');
      }
      expect(state.rejected, [for (var day = 3; day <= 7; day++) '2026-10-0${day}T00:00:00Z']);
    });

    test('an unreadable state file reads as empty', () async {
      await File(p.join(work.path, 'rulesets-state.json')).writeAsString('{not json');
      final state = await store().readState();
      expect(state.pending, isNull);
      expect(state.rejected, isEmpty);
    });

    test('fields of the wrong type read as absent', () {
      final state = RulesetState.fromJson(const {'pending': 5, 'rejected': 'x', 'last_check': 'yesterday'});
      expect(state.pending, isNull);
      expect(state.rejected, isEmpty);
      expect(state.lastCheck, isNull);
    });
  });

  // The digest gate itself. A file of the right name with the wrong contents
  // used to pass an existence check forever, and the only symptom was the core
  // refusing to start.
  group('allFilesMatch', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory(p.join(work.path, 'match')).create();
    });

    Future<RulesetManifestFile> writeFile(String name, List<int> content) async {
      await File(p.join(dir.path, name)).writeAsBytes(content, flush: true);
      return RulesetManifestFile(name: name, sha256: digest(content));
    }

    RulesetManifest of(List<RulesetManifestFile> files) => RulesetManifest(version: bundleVersion, files: files);

    test('accepts files whose digests match the manifest', () async {
      final manifest = of([
        await writeFile('direct-private.srs', [1, 2, 3]),
        await writeFile('direct-apple.srs', [4]),
      ]);
      expect(await RulesetStore.allFilesMatch(dir, manifest), isTrue);
    });

    test('accepts an empty manifest', () async {
      expect(await RulesetStore.allFilesMatch(dir, of([])), isTrue);
    });

    test('rejects a missing file', () async {
      final manifest = of([
        await writeFile('direct-private.srs', [1, 2, 3]),
        RulesetManifestFile(name: 'direct-apple.srs', sha256: digest([])),
      ]);
      expect(await RulesetStore.allFilesMatch(dir, manifest), isFalse);
    });

    test('rejects a file whose contents changed', () async {
      final entry = await writeFile('direct-regional-sites.srs', [1, 2, 3, 4]);
      await File(p.join(dir.path, entry.name)).writeAsBytes([9, 9, 9, 9], flush: true);
      expect(await RulesetStore.allFilesMatch(dir, of([entry])), isFalse);
    });

    // Truncation is the realistic corruption: an interrupted write.
    test('rejects a truncated file', () async {
      final entry = await writeFile('direct-regional-ips.srs', [1, 2, 3, 4, 5, 6, 7, 8]);
      await File(p.join(dir.path, entry.name)).writeAsBytes([1, 2, 3, 4], flush: true);
      expect(await RulesetStore.allFilesMatch(dir, of([entry])), isFalse);
    });

    test('rejects an empty file where content was expected', () async {
      final entry = await writeFile('direct-apple.srs', [1, 2, 3]);
      await File(p.join(dir.path, entry.name)).writeAsBytes([], flush: true);
      expect(await RulesetStore.allFilesMatch(dir, of([entry])), isFalse);
    });

    test('accepts an uppercase digest in the manifest', () async {
      final entry = await writeFile('direct-private.srs', [1, 2, 3]);
      final upper = RulesetManifestFile(name: entry.name, sha256: entry.sha256.toUpperCase());
      expect(await RulesetStore.allFilesMatch(dir, of([upper])), isTrue);
    });

    test('rejects when the directory does not exist', () async {
      final manifest = of([RulesetManifestFile(name: 'direct-private.srs', sha256: digest([]))]);
      expect(await RulesetStore.allFilesMatch(Directory(p.join(dir.path, 'nope')), manifest), isFalse);
    });
  });

  group('RulesetManifestFile', () {
    test('parses name, sha256 and size', () {
      final file = RulesetManifestFile.fromJson(const {
        'name': 'direct-private.srs',
        'sha256': '260491243e0266e5ba543f509ca7f13b07d6f4c2c26ade3f675ddea1661f3213',
        'size': 754,
      });
      expect(file.name, 'direct-private.srs');
      expect(file.sha256, '260491243e0266e5ba543f509ca7f13b07d6f4c2c26ade3f675ddea1661f3213');
      expect(file.size, 754);
    });

    test('size is optional', () {
      expect(RulesetManifestFile.fromJson(const {'name': 'direct-private.srs', 'sha256': 'ab'}).size, isNull);
    });

    // sha256 is required so a manifest that omits it fails loudly rather than
    // downgrading the check to "the file exists".
    test('throws when sha256 is absent', () {
      expect(
        () => RulesetManifestFile.fromJson(const {'name': 'direct-private.srs', 'size': 754}),
        throwsA(isA<TypeError>()),
      );
    });
  });
}

class _FakeBundle implements RulesetBundle {
  _FakeBundle(RulesetManifest manifest, this.files) : json = jsonEncode(manifest.toJson());

  final String json;
  final Map<String, List<int>> files;

  @override
  Future<String> manifestJson() async => json;

  @override
  Future<Uint8List> file(String name) async => Uint8List.fromList(files[name]!);
}
