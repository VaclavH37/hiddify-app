import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:hiddify/core/rulesets/ruleset_store.dart';
import 'package:hiddify/features/connection/data/ruleset_start_guard.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:path/path.dart' as p;

/// A downloaded rule-set the core cannot load stops every connect until it
/// is gone. The guard wraps each core start: it confirms a download the core
/// loaded, and when one stops the core it puts the bundle back, rejects that
/// version, and starts once more.
void main() {
  // The shapes the start paths really produce (rayn_core_service.dart).
  const desktopRuleSetFailure =
      'startFailed - failed to start core START_SERVICE start service: initialize router: '
      'parse rule-set[4]: unsupported version: 6';
  const mobileRuleSetFailure = 'startService - initialize router: parse rule-set[4]: unsupported version: 6';
  const restartRuleSetFailure = 'START_SERVICE initialize router: parse rule-set[4]: unsupported version: 6';
  const otherStartFailure = 'startService - start inbound/tun[tun-in]: configure tun interface: access denied';

  group('coreStartFailureMessage', () {
    test('recognises a refused start from every start path', () {
      for (final message in [desktopRuleSetFailure, mobileRuleSetFailure, restartRuleSetFailure, otherStartFailure]) {
        expect(coreStartFailureMessage(ConnectionFailure.unexpected(message)), message);
      }
      expect(coreStartFailureMessage(const ConnectionFailure.unexpected('createService - boom')), isNotNull);
    });

    test('ignores failures that are not the core refusing to start', () {
      for (final failure in [
        const ConnectionFailure.unexpected('background core is not started yet!'),
        const ConnectionFailure.unexpected('failed to start background core'),
        const ConnectionFailure.unexpected('stored configuration is unavailable; refresh the subscription'),
        const ConnectionFailure.unexpected(),
        const ConnectionFailure.missingVpnPermission('startService - denied'),
        const ConnectionFailure.invalidConfig('rule-set'),
      ]) {
        expect(coreStartFailureMessage(failure), isNull, reason: '$failure');
      }
    });

    test('a rule-set is named however sing-box spells it', () {
      expect(namesRuleSet('parse rule-set[2]: unexpected EOF'), isTrue);
      expect(namesRuleSet('rule_set not found'), isTrue);
      expect(namesRuleSet('RuleSet missing'), isTrue);
      expect(namesRuleSet('configure tun interface: access denied'), isFalse);
    });
  });

  group('rulesetStartAction', () {
    RulesetStartAction action(String? message, {bool pending = false, bool download = true}) =>
        rulesetStartAction(coreMessage: message, pending: pending, downloadInstalled: download);

    test('a named rule-set with a download installed reverts and retries, pending or not', () {
      expect(action(mobileRuleSetFailure, pending: true), RulesetStartAction.revertAndRetry);
      expect(action(mobileRuleSetFailure), RulesetStartAction.revertAndRetry);
    });

    test('another core-start failure reverts only a download still pending, without a retry', () {
      expect(action(otherStartFailure, pending: true), RulesetStartAction.revert);
      expect(action(otherStartFailure), RulesetStartAction.none);
    });

    test('nothing to do with the bundle installed, or for a failure that is not a refused start', () {
      expect(action(mobileRuleSetFailure, pending: true, download: false), RulesetStartAction.none);
      expect(action(null, pending: true), RulesetStartAction.none);
    });
  });

  group('RulesetStartGuard', () {
    const bundleVersion = '2026-09-20T13:54:30Z';
    const downloaded = '2026-10-05T18:30:00Z';
    final bundleFiles = <String, List<int>>{
      'direct-private.srs': [1, 1, 1],
      'block-ads.srs': [2, 2, 2, 2],
    };
    final downloadedFiles = <String, List<int>>{
      ...bundleFiles,
      'block-ads.srs': <int>[3, 3, 3],
    };

    RulesetManifest manifestOf(String version, Map<String, List<int>> files) => RulesetManifest(
      version: version,
      fetchedAt: version,
      files: [
        for (final MapEntry(key: name, value: bytes) in files.entries)
          RulesetManifestFile(name: name, sha256: sha256.convert(bytes).toString(), size: bytes.length),
      ],
    );

    late Directory work;
    late RulesetStore store;
    late List<Either<ConnectionFailure, Unit>> results;
    late int starts;

    setUp(() async {
      work = await Directory.systemTemp.createTemp('ruleset_start_guard_test');
      store = RulesetStore(
        work,
        bundle: _FakeBundle(manifestOf(bundleVersion, bundleFiles), bundleFiles),
        renameRetries: const [],
      );
      await store.ensureInstalled();
      results = [];
      starts = 0;
    });

    tearDown(() async {
      if (work.existsSync()) await work.delete(recursive: true);
    });

    Future<Either<ConnectionFailure, Unit>> start() async => results[starts++];

    Future<void> installDownload() async {
      final result = await store.installDownloaded(manifestOf(downloaded, downloadedFiles), {
        'block-ads.srs': downloadedFiles['block-ads.srs']!,
      });
      expect(result.status, RulesetInstallStatus.installed);
    }

    Future<List<int>> blockAdsOnDisk() => File(p.join(work.path, 'rulesets', 'block-ads.srs')).readAsBytes();

    Either<ConnectionFailure, Unit> failWith(String message) => left(ConnectionFailure.unexpected(message));

    test('a start that succeeds confirms the pending download', () async {
      await installDownload();
      results = [right(unit)];

      expect(await RulesetStartGuard(store).run(start), right<ConnectionFailure, Unit>(unit));
      expect(starts, 1);
      expect((await store.readState()).pending, isNull);
      expect(await blockAdsOnDisk(), downloadedFiles['block-ads.srs']);
    });

    test('a download the core cannot load is replaced by the bundle, rejected, and the start retried', () async {
      await installDownload();
      results = [failWith(mobileRuleSetFailure), right(unit)];

      expect(await RulesetStartGuard(store).run(start), right<ConnectionFailure, Unit>(unit));
      expect(starts, 2);
      expect(await blockAdsOnDisk(), bundleFiles['block-ads.srs']);
      final state = await store.readState();
      expect(state.rejected, [downloaded]);
      expect(state.pending, isNull);
      expect(await store.installedDownloadVersion(), isNull);
    });

    test('a retry that fails too returns its own failure, on the bundle', () async {
      await installDownload();
      results = [failWith(desktopRuleSetFailure), failWith(otherStartFailure)];

      final result = await RulesetStartGuard(store).run(start);
      expect(result.getLeft().toNullable(), const ConnectionFailure.unexpected(otherStartFailure));
      expect(starts, 2);
      expect(await blockAdsOnDisk(), bundleFiles['block-ads.srs']);
    });

    test('another core-start failure reverts a pending download without retrying', () async {
      await installDownload();
      results = [failWith(otherStartFailure)];

      final result = await RulesetStartGuard(store).run(start);
      expect(result.isLeft(), isTrue);
      expect(starts, 1);
      expect(await blockAdsOnDisk(), bundleFiles['block-ads.srs']);
      expect((await store.readState()).rejected, [downloaded]);
    });

    test('a confirmed download is kept through a failure that does not name a rule-set', () async {
      await installDownload();
      await store.confirmPending();
      results = [failWith(otherStartFailure)];

      await RulesetStartGuard(store).run(start);
      expect(starts, 1);
      expect(await blockAdsOnDisk(), downloadedFiles['block-ads.srs']);
      expect((await store.readState()).rejected, isEmpty);
    });

    test('the bundle is left alone, and nothing retried, when no download is installed', () async {
      results = [failWith(mobileRuleSetFailure)];

      final result = await RulesetStartGuard(store).run(start);
      expect(result.isLeft(), isTrue);
      expect(starts, 1);
      expect((await store.readState()).rejected, isEmpty);
    });

    test('a failure that is not a refused start leaves a pending download alone', () async {
      await installDownload();
      results = [left(const ConnectionFailure.missingVpnPermission())];

      await RulesetStartGuard(store).run(start);
      expect(starts, 1);
      expect(await blockAdsOnDisk(), downloadedFiles['block-ads.srs']);
      expect((await store.readState()).pending, downloaded);
    });

    // Windows: a core that just failed to start can still hold the files.
    test('when the files cannot be replaced now, the rejection still restores the bundle at the next launch', () async {
      await installDownload();
      Future<void> refuse(File from, String to) async => throw FileSystemException('in use', to);
      final locked = RulesetStore(
        work,
        bundle: _FakeBundle(manifestOf(bundleVersion, bundleFiles), bundleFiles),
        renameRetries: const [],
        rename: refuse,
      );
      results = [failWith(mobileRuleSetFailure)];

      final result = await RulesetStartGuard(locked).run(start);
      expect(result.isLeft(), isTrue);
      expect(starts, 1, reason: 'a retry would meet the same files');
      expect((await store.readState()).rejected, [downloaded]);

      expect(await store.ensureInstalled(), isTrue);
      expect(await blockAdsOnDisk(), bundleFiles['block-ads.srs']);
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
