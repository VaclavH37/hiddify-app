import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:loggy/loggy.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Extracts bundled CN routing rule-sets (`assets/rulesets/*.srs`) into the
/// Go core's working directory so sing-box can load them as `Type: Local`
/// rule-sets.
///
/// [basePath] MUST be the core's working dir (CWD): in the gRPC service mode the
/// core `os.Chdir()`s to the working path and the `filemanager.WithDefault` base
/// is unset, so relative Local rule-set paths (`rulesets/*.srs`) resolve against
/// CWD. Extracting anywhere else makes every `RuleSet:`-keyed rule fail to open
/// and the core refuses to start. See bootstrap.dart for the call site.
///
/// baseDir and workingDir are now identical on every platform. They diverged on
/// Android until the working dir moved off external storage, and getting this
/// argument wrong was how that bug originally surfaced — so the parameter stays
/// explicit rather than being inferred.
///
/// Rule-sets must be on disk before the first VPN start: the Go core opens the
/// file at config-load time, and a missing file makes the entire `RuleSet:`-
/// keyed DNS / route rule inert. Bundling + extracting avoids the chicken-and-
/// egg of trying to download rule-sets from `raw.githubusercontent.com` on
/// first launch inside the GFW.
///
/// Re-extraction is gated on `<basePath>/rulesets/MANIFEST` matching the bundled
/// one on BOTH counts: the same `version`, and every listed file present on disk
/// with the expected sha256. When either differs, every file is rewritten and the
/// on-disk MANIFEST is updated last (so a crash mid-extract leaves the previous
/// version marker behind and we retry on the next launch).
///
/// The digest check is what makes that self-healing. An existence check alone
/// let a truncated or corrupted `.srs` — an interrupted extract, a half-written
/// file from a device that lost power — survive every subsequent launch, because
/// the version marker had already been written. The failure surfaced far from its
/// cause: the core opens Local rule-sets at config-load time, so a bad file means
/// "failed to start background core" with nothing pointing at the rule-set.
abstract class RulesetExtractor {
  static const _bundleAssetPath = 'assets/rulesets/MANIFEST';
  static const _bundleAssetDir = 'assets/rulesets';
  static const _onDiskDirName = 'rulesets';
  static const _onDiskManifestName = 'MANIFEST';

  static final _log = Loggy('ruleset_extractor');

  /// Ensures the on-disk rule-sets at [basePath]/rulesets/ match the bundled
  /// MANIFEST. Returns true if any extraction happened, false if everything
  /// was already current.
  static Future<bool> ensureExtracted(Directory basePath) async {
    final RulesetManifest bundleManifest;
    try {
      final raw = await rootBundle.loadString(_bundleAssetPath);
      bundleManifest = RulesetManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      _log.error('failed to read bundled rule-set MANIFEST', e, st);
      rethrow;
    }

    final targetDir = Directory(p.join(basePath.path, _onDiskDirName));
    final onDiskManifest = await _readOnDiskManifest(targetDir);

    if (onDiskManifest != null &&
        onDiskManifest.version == bundleManifest.version &&
        await allFilesMatch(targetDir, bundleManifest)) {
      _log.debug('rule-sets up to date (version ${bundleManifest.version})');
      return false;
    }

    _log.info('extracting rule-sets: on-disk=${onDiskManifest?.version ?? "<none>"} bundle=${bundleManifest.version}');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    for (final file in bundleManifest.files) {
      await _extractFile(targetDir, file.name);
    }

    await _pruneStale(targetDir, bundleManifest);

    // Manifest written last so a crash above leaves the previous version
    // marker on disk and we re-enter the extraction branch next launch.
    final manifestJson = await rootBundle.loadString(_bundleAssetPath);
    final manifestFile = File(p.join(targetDir.path, _onDiskManifestName));
    await manifestFile.writeAsString(manifestJson, flush: true);

    _log.info('rule-sets extracted (${bundleManifest.files.length} files, version ${bundleManifest.version})');
    return true;
  }

  static Future<RulesetManifest?> _readOnDiskManifest(Directory targetDir) async {
    final manifestFile = File(p.join(targetDir.path, _onDiskManifestName));
    if (!await manifestFile.exists()) return null;
    try {
      final raw = await manifestFile.readAsString();
      return RulesetManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e, st) {
      _log.warning('on-disk MANIFEST unreadable, treating as version mismatch', e, st);
      return null;
    }
  }

  /// True when every file the [manifest] lists is on disk in [targetDir] AND
  /// hashes to the digest recorded for it. Any mismatch returns false, which
  /// puts the caller into the re-extraction branch.
  ///
  /// This reads every rule-set into memory on each cold start. That is fine at
  /// the current bundle size (four files, ~91 KB total — well under a
  /// millisecond of hashing) and the check is worth far more than it costs, but
  /// it is a per-launch cost proportional to the bundle: revisit if the rule-set
  /// set ever grows by an order of magnitude.
  ///
  /// A genuinely corrupt asset in the bundle makes this return false forever, so
  /// the app re-extracts on every launch. That is deliberate — re-extracting
  /// 91 KB is cheap, it is logged, and the alternative is running with rule-sets
  /// the core will reject anyway.
  @visibleForTesting
  static Future<bool> allFilesMatch(Directory targetDir, RulesetManifest manifest) async {
    for (final file in manifest.files) {
      final onDisk = File(p.join(targetDir.path, file.name));
      try {
        if (!await onDisk.exists()) {
          _log.info('rule-set ${file.name} missing, re-extracting');
          return false;
        }
        final digest = sha256.convert(await onDisk.readAsBytes()).toString();
        if (digest != file.sha256.toLowerCase()) {
          // Log the name and the verdict, never the digests — they are not
          // secret, but a mismatch line full of hex is unreadable in a bug
          // report and the name is what identifies the file to re-extract.
          _log.warning('rule-set ${file.name} failed checksum, re-extracting');
          return false;
        }
      } on FileSystemException catch (e) {
        _log.warning('rule-set ${file.name} unreadable, re-extracting: $e');
        return false;
      }
    }
    return true;
  }

  /// Deletes `*.srs` files that are no longer listed in the bundled MANIFEST.
  /// Without this, a rule-set dropped from the bundle lingers on disk forever on
  /// upgraded installs — `fakeip-remote-sites.srs` (167 KB) was left behind when
  /// the FakeIP path was removed. Best-effort: a failure here is not fatal, the
  /// stale file is unreferenced by builder.go either way.
  static Future<void> _pruneStale(Directory targetDir, RulesetManifest manifest) async {
    final expected = manifest.files.map((f) => f.name).toSet();
    try {
      await for (final entity in targetDir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.srs') || expected.contains(name)) continue;
        try {
          await entity.delete();
          _log.info('pruned stale rule-set $name');
        } catch (e) {
          _log.warning('failed to prune stale rule-set $name: $e');
        }
      }
    } catch (e, st) {
      _log.warning('rule-set prune scan failed', e, st);
    }
  }

  static Future<void> _extractFile(Directory targetDir, String name) async {
    final bytes = await rootBundle.load('$_bundleAssetDir/$name');
    final tmp = File(p.join(targetDir.path, '$name.tmp'));
    await tmp.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
    await tmp.rename(p.join(targetDir.path, name));
  }
}
