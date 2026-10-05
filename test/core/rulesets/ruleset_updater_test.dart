import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:hiddify/core/rulesets/ruleset_store.dart';
import 'package:hiddify/core/rulesets/ruleset_updater.dart';
import 'package:hiddify/core/rulesets/srs_check.dart';

/// The updater asks the mirror for a newer manifest while connected, fetches
/// only the files that changed, and hands them to the store. Whatever the
/// mirror or the network does, the worst outcome must be "nothing installed".
void main() {
  const base = 'https://mirror.example';
  const bundleVersion = '2026-09-20T13:54:30Z';
  const newer = '2026-10-05T18:30:00Z';
  final now = DateTime.utc(2026, 10, 6, 9);

  Uint8List srs(int seed, {int version = 1}) => Uint8List.fromList([
    0x53,
    0x52,
    0x53,
    version,
    ...zlib.encode([1, seed]),
  ]);
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

  final bundleFiles = <String, List<int>>{'direct-private.srs': srs(1), 'block-ads.srs': srs(2)};

  /// What the mirror publishes: the bundle with block-ads changed.
  final published = <String, List<int>>{...bundleFiles, 'block-ads.srs': srs(3)};

  group('mirrorDecision', () {
    final installed = manifestOf(bundleVersion, bundleFiles);

    MirrorDecision decide(RulesetManifest remote, {Set<String> rejected = const {}}) =>
        mirrorDecision(remote, installed: installed, rejected: rejected);

    test('fetches only the files whose digest changed', () {
      final decision = decide(manifestOf(newer, published));
      expect(decision, isA<MirrorDownload>());
      expect((decision as MirrorDownload).files.map((f) => f.name), ['block-ads.srs']);
    });

    test('nothing newer, or a rejected version, is up to date', () {
      expect(decide(manifestOf(bundleVersion, published)), isA<MirrorUpToDate>());
      expect(decide(manifestOf('2026-09-01T00:00:00Z', published)), isA<MirrorUpToDate>());
      expect(decide(manifestOf(newer, published), rejected: {newer}), isA<MirrorUpToDate>());
    });

    test('refuses a set that is not for this build', () {
      expect(decide(manifestOf(newer, published, schema: kRulesetSchema + 1)), isA<MirrorRefused>());
      expect(decide(manifestOf(newer, {...published, 'extra.srs': srs(9)})), isA<MirrorRefused>());
      expect(decide(manifestOf(newer, {'direct-private.srs': srs(1)})), isA<MirrorRefused>());
      expect(decide(manifestOf('latest', published)), isA<MirrorRefused>());
    });

    test('refuses a file listed twice', () {
      final remote = manifestOf(newer, published);
      final twice = remote.copyWith(files: [...remote.files, remote.files.first]);
      expect(decide(twice), isA<MirrorRefused>());
    });

    test('refuses a malformed digest or a missing size', () {
      final remote = manifestOf(newer, published);
      RulesetManifest withFirst(RulesetManifestFile file) => remote.copyWith(files: [file, ...remote.files.skip(1)]);
      final first = remote.files.first;
      expect(decide(withFirst(first.copyWith(sha256: first.sha256.toUpperCase()))), isA<MirrorRefused>());
      expect(decide(withFirst(first.copyWith(sha256: 'abc'))), isA<MirrorRefused>());
      expect(decide(withFirst(first.copyWith(size: null))), isA<MirrorRefused>());
      expect(decide(withFirst(first.copyWith(size: 0))), isA<MirrorRefused>());
    });

    test('refuses a file or a set over the caps before anything is fetched', () {
      final remote = manifestOf(newer, published);
      final first = remote.files.first;
      final bigFile = remote.copyWith(
        files: [
          first.copyWith(size: rulesetMaxFileBytes + 1),
          ...remote.files.skip(1),
        ],
      );
      expect(decide(bigFile), isA<MirrorRefused>());
      final bigSet = remote.copyWith(files: [for (final f in remote.files) f.copyWith(size: rulesetMaxFileBytes)]);
      expect(decide(bigSet), isA<MirrorRefused>());
    });
  });

  group('RulesetUpdate', () {
    late Directory work;
    late RulesetStore store;
    late Map<String, List<int>> responses;
    late List<String> fetched;

    setUp(() async {
      work = await Directory.systemTemp.createTemp('ruleset_updater_test');
      store = RulesetStore(
        work,
        bundle: _FakeBundle(manifestOf(bundleVersion, bundleFiles), bundleFiles),
        renameRetries: const [],
      );
      await store.ensureInstalled();
      responses = {};
      fetched = [];
    });

    tearDown(() async {
      if (work.existsSync()) await work.delete(recursive: true);
    });

    Future<Uint8List> fetch(String url, int maxBytes) async {
      fetched.add(url);
      final body = responses[url];
      if (body == null) {
        throw DioException(
          requestOptions: RequestOptions(path: url),
          type: DioExceptionType.connectionError,
        );
      }
      if (body.length > maxBytes) throw ResponseTooLargeException(maxBytes);
      return Uint8List.fromList(body);
    }

    RulesetUpdate update({DateTime? at}) =>
        RulesetUpdate(store: store, fetch: fetch, base: base, clock: () => at ?? now);

    String manifestUrl() => '$base/v$kRulesetSchema/MANIFEST';
    String fileUrl(List<int> bytes) => '$base/v$kRulesetSchema/files/${digest(bytes)}.srs';

    /// Publishes [manifest] and every file it lists, served at [files].
    void publish(RulesetManifest manifest, Map<String, List<int>> files) {
      responses[manifestUrl()] = utf8.encode(jsonEncode(manifest.toJson()));
      for (final bytes in files.values) {
        responses[fileUrl(bytes)] = bytes;
      }
    }

    Future<String> installedVersion() async => (await store.installedManifest())!.version;

    test('installs a newer set, fetching only what changed', () async {
      publish(manifestOf(newer, published), published);

      expect(await update().run(), rulesetCheckInterval);
      expect(fetched, [manifestUrl(), fileUrl(published['block-ads.srs']!)]);
      expect(await installedVersion(), newer);
      final state = await store.readState();
      expect(state.pending, newer);
      expect(state.lastCheck, now);
    });

    test('asks for the manifest only, when nothing is newer', () async {
      publish(manifestOf(bundleVersion, bundleFiles), bundleFiles);

      expect(await update().run(), rulesetCheckInterval);
      expect(fetched, [manifestUrl()]);
      expect((await store.readState()).lastCheck, now);
    });

    test('does not ask again within a day of the last answer', () async {
      await store.recordCheck(now.subtract(const Duration(hours: 2)));
      publish(manifestOf(newer, published), published);

      expect(await update().run(), const Duration(hours: 22));
      expect(fetched, isEmpty);
    });

    test('asks again when the clock has gone back past the last answer', () async {
      await store.recordCheck(now.add(const Duration(days: 3)));
      publish(manifestOf(newer, published), published);

      await update().run();
      expect(await installedVersion(), newer);
    });

    test('an unreachable mirror retries within the hour and records nothing', () async {
      expect(await update().run(), rulesetRetryAfterFailure);
      expect(fetched, [manifestUrl()]);
      expect((await store.readState()).lastCheck, isNull);
    });

    test('an unreadable manifest retries within the hour', () async {
      responses[manifestUrl()] = utf8.encode('<html>not json</html>');
      expect(await update().run(), rulesetRetryAfterFailure);
      expect(await installedVersion(), bundleVersion);
    });

    test('a file that cannot be fetched installs nothing and retries within the hour', () async {
      publish(manifestOf(newer, published), {});

      expect(await update().run(), rulesetRetryAfterFailure);
      expect(await installedVersion(), bundleVersion);
      expect((await store.readState()).lastCheck, isNull);
    });

    test('bytes that do not match their digest install nothing', () async {
      publish(manifestOf(newer, published), {});
      responses[fileUrl(published['block-ads.srs']!)] = srs(4);

      expect(await update().run(), rulesetCheckInterval);
      expect(await installedVersion(), bundleVersion);
      expect((await store.readState()).lastCheck, now);
    });

    // The digest matches, so only the format check stands between this file
    // and a core that cannot start.
    test('a file in a format this core cannot read installs nothing', () async {
      final tooNew = {...bundleFiles, 'block-ads.srs': srs(3, version: kMaxSrsVersion + 1)};
      publish(manifestOf(newer, tooNew), tooNew);

      await update().run();
      expect(await installedVersion(), bundleVersion);
    });

    test('a set for another schema is never downloaded', () async {
      publish(manifestOf(newer, published, schema: kRulesetSchema + 1), published);

      await update().run();
      expect(fetched, [manifestUrl()]);
      expect(await installedVersion(), bundleVersion);
    });

    test('a version rejected before is never downloaded', () async {
      publish(manifestOf(newer, published), published);
      await update().run();
      await store.revertToBundled(reject: newer);
      fetched.clear();

      await update(at: now.add(const Duration(days: 2))).run();
      expect(fetched, [manifestUrl()]);
      expect(await installedVersion(), bundleVersion);
    });
  });

  group('describeMirrorError', () {
    final options = RequestOptions(path: '$base/v1/MANIFEST');

    test('names the kind, never the URL', () {
      expect(
        describeMirrorError(DioException(requestOptions: options, type: DioExceptionType.connectionTimeout)),
        'connectionTimeout',
      );
      expect(
        describeMirrorError(
          DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: options, statusCode: 404),
          ),
        ),
        'HTTP 404',
      );
      expect(describeMirrorError(const FormatException('bad', 'https://mirror.example')), 'unreadable manifest');
      expect(describeMirrorError(const ResponseTooLargeException(10)), contains('10 bytes'));
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
