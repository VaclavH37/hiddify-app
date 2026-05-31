import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

/// Extracts bundled CN routing rule-sets (`assets/rulesets/*.srs`) into the
/// Go core's working directory so sing-box can load them as `Type: Local`
/// rule-sets.
///
/// [basePath] MUST be the core's working dir (CWD), not the app support dir:
/// in the gRPC service mode the core `os.Chdir()`s to the working path and the
/// `filemanager.WithDefault` base is unset, so relative Local rule-set paths
/// (`rulesets/*.srs`) resolve against CWD. On Android the internal filesDir
/// (baseDir) and external files dir (workingDir) are different directories —
/// extracting to the wrong one makes every `RuleSet:`-keyed rule fail to open
/// and the core refuses to start. See bootstrap.dart for the call site.
///
/// Rule-sets must be on disk before the first VPN start: the Go core opens the
/// file at config-load time, and a missing file makes the entire `RuleSet:`-
/// keyed DNS / route rule inert. Bundling + extracting avoids the chicken-and-
/// egg of trying to download rule-sets from `raw.githubusercontent.com` on
/// first launch inside the GFW.
///
/// Re-extraction is gated by a one-field version compare against
/// `<basePath>/rulesets/MANIFEST`: when the bundle MANIFEST in the AAB has a
/// different `version`, every file is rewritten and the on-disk MANIFEST is
/// updated last (so a crash mid-extract leaves the previous version marker
/// behind and we retry on the next launch).
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
        await _allFilesPresent(targetDir, bundleManifest)) {
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

  static Future<bool> _allFilesPresent(Directory targetDir, RulesetManifest manifest) async {
    for (final file in manifest.files) {
      if (!await File(p.join(targetDir.path, file.name)).exists()) {
        return false;
      }
    }
    return true;
  }

  static Future<void> _extractFile(Directory targetDir, String name) async {
    final bytes = await rootBundle.load('$_bundleAssetDir/$name');
    final tmp = File(p.join(targetDir.path, '$name.tmp'));
    await tmp.writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
    await tmp.rename(p.join(targetDir.path, name));
  }
}
