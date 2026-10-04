import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:loggy/loggy.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Where the bundled rule-sets come from: the asset bundle in the app, bytes
/// in tests.
abstract interface class RulesetBundle {
  Future<String> manifestJson();
  Future<Uint8List> file(String name);
}

class AssetRulesetBundle implements RulesetBundle {
  const AssetRulesetBundle();

  static const _dir = 'assets/rulesets';

  @override
  Future<String> manifestJson() => rootBundle.loadString('$_dir/MANIFEST');

  @override
  Future<Uint8List> file(String name) async {
    final data = await rootBundle.load('$_dir/$name');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

enum RulesetChoice { keepInstalled, extractBundled }

/// Decides, at launch, whether the rule-sets on disk stay or the bundle
/// replaces them. The bundle wins whenever the installed set could be wrong
/// for this build: missing, another schema or file list, an unreadable or
/// rejected version, older than the bundle, or a file failing its digest.
/// A downloaded set newer than the bundle stays; the bundle only overwrites
/// it when this build ships something newer.
@visibleForTesting
({RulesetChoice choice, String reason}) chooseInstalled({
  required RulesetManifest bundled,
  required RulesetManifest? installed,
  required bool installedIntact,
  required Set<String> rejected,
}) {
  const extract = RulesetChoice.extractBundled;
  if (installed == null) return (choice: extract, reason: 'no rule-sets on disk');
  if (installed.schema != bundled.schema) {
    return (choice: extract, reason: 'schema ${installed.schema} on disk, this build loads ${bundled.schema}');
  }
  if (!_sameNames(installed, bundled)) return (choice: extract, reason: "file list differs from this build's");
  final installedTime = installed.versionTime;
  if (installedTime == null) return (choice: extract, reason: 'unreadable version ${installed.version}');
  if (rejected.contains(installed.version)) {
    return (choice: extract, reason: 'version ${installed.version} was rejected');
  }
  final bundledTime = bundled.versionTime;
  if (bundledTime == null ? installed.version != bundled.version : installedTime.isBefore(bundledTime)) {
    return (choice: extract, reason: "${installed.version} is older than this build's ${bundled.version}");
  }
  if (!installedIntact) return (choice: extract, reason: 'a file fails its digest');
  final downloaded = bundledTime != null && installedTime.isAfter(bundledTime);
  return (choice: RulesetChoice.keepInstalled, reason: downloaded ? 'downloaded ${installed.version}' : 'current');
}

bool _sameNames(RulesetManifest a, RulesetManifest b) =>
    a.fileNames.length == b.fileNames.length && a.fileNames.containsAll(b.fileNames);

/// What the store remembers between launches, beside the files themselves
/// (`<workingDir>/rulesets-state.json`). Not SharedPreferences: bootstrap
/// installs rule-sets before preferences are initialised.
@immutable
class RulesetState {
  const RulesetState({this.pending, this.rejected = const [], this.lastCheck});

  /// A downloaded version that has not yet been through a successful core
  /// start. A start that fails while one is pending reverts to the bundle.
  final String? pending;

  /// Versions that failed, newest last, at most [RulesetStore.maxRejected].
  /// Never installed again.
  final List<String> rejected;

  /// When the mirror was last asked for a newer manifest.
  final DateTime? lastCheck;

  RulesetState withPending(String? version) => RulesetState(pending: version, rejected: rejected, lastCheck: lastCheck);

  RulesetState withRejected(String version) {
    final next = [...rejected.where((v) => v != version), version];
    final start = next.length > RulesetStore.maxRejected ? next.length - RulesetStore.maxRejected : 0;
    return RulesetState(pending: pending, rejected: next.sublist(start), lastCheck: lastCheck);
  }

  RulesetState withLastCheck(DateTime at) => RulesetState(pending: pending, rejected: rejected, lastCheck: at);

  Map<String, dynamic> toJson() => {
    if (pending != null) 'pending': pending,
    'rejected': rejected,
    if (lastCheck != null) 'last_check': lastCheck!.toUtc().toIso8601String(),
  };

  /// Tolerant: a field of the wrong type reads as absent. The worst a lost
  /// state file costs is one extra download, or a rejected version offered
  /// once more and refused again by the core start that rejected it.
  factory RulesetState.fromJson(Map<String, dynamic> json) {
    final pending = json['pending'];
    final rejected = json['rejected'];
    final lastCheck = json['last_check'];
    return RulesetState(
      pending: pending is String ? pending : null,
      rejected: rejected is List ? rejected.whereType<String>().toList() : const [],
      lastCheck: lastCheck is String ? DateTime.tryParse(lastCheck)?.toUtc() : null,
    );
  }
}

enum RulesetInstallStatus { installed, staged, refused }

@immutable
class RulesetInstallResult {
  const RulesetInstallResult(this.status, this.detail);

  final RulesetInstallStatus status;

  /// For the log: how many files changed, or why nothing did.
  final String detail;

  @override
  String toString() => '${status.name}: $detail';
}

typedef RulesetRename = Future<void> Function(File from, String to);

/// The rule-sets the Go core loads, at `<workingDir>/rulesets/*.srs`.
///
/// [workingDir] MUST be the core's working directory: the core `os.Chdir()`s
/// there and resolves its relative `rulesets/*.srs` paths against it. Anywhere
/// else, every rule-set fails to open and the core refuses to start. On iOS
/// this is the App Group's `Working` folder, which the tunnel extension reads;
/// on the other platforms it is the app support folder.
///
/// Two sources fill it. The bundle, extracted at launch, is the baseline every
/// install starts from and the fallback whenever anything is wrong. A set
/// downloaded from the Rayn mirror replaces it while the app is connected; the
/// core watches each file and reloads it live when it is renamed into place.
/// [chooseInstalled] decides between them at launch.
///
/// A missing or corrupt rule-set is fatal to the next core start, so every
/// write lands beside its target as `.tmp`, is verified, and is renamed over
/// it. The MANIFEST is written last: a crash part-way leaves files that
/// disagree with it, and the next launch restores the bundle.
///
/// On Windows the core keeps rule-set files open without delete sharing until
/// Go's garbage collector closes them, so a rename over a loaded file can be
/// refused. Renames are retried; when they still fail, a download is staged in
/// `rulesets-staged/` and installed at the next launch, before the core starts.
///
/// Every operation runs under one process-wide lock.
class RulesetStore {
  RulesetStore(
    this.workingDir, {
    this.bundle = const AssetRulesetBundle(),
    List<Duration> renameRetries = defaultRenameRetries,
    RulesetRename? rename,
  }) : _renameRetries = renameRetries,
       _rename = rename ?? _defaultRename;

  static const maxRejected = 5;
  static const defaultRenameRetries = [Duration(seconds: 1), Duration(seconds: 3), Duration(seconds: 6)];
  static const _manifestName = 'MANIFEST';

  static final _log = Loggy('ruleset_store');

  final Directory workingDir;
  final RulesetBundle bundle;
  final List<Duration> _renameRetries;
  final RulesetRename _rename;

  Directory get dir => Directory(p.join(workingDir.path, 'rulesets'));
  Directory get stagedDir => Directory(p.join(workingDir.path, 'rulesets-staged'));
  File get _stateFile => File(p.join(workingDir.path, 'rulesets-state.json'));

  static Future<void> _defaultRename(File from, String to) => from.rename(to);

  static Future<void> _tail = Future.value();

  static Future<T> _locked<T>(Future<T> Function() body) {
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    return previous.then((_) => body()).whenComplete(done.complete);
  }

  /// Launch: installs a staged download, then keeps the installed set or
  /// extracts the bundle over it. Returns true when the bundle was extracted.
  /// Must finish before the core starts.
  Future<bool> ensureInstalled() => _locked(() async {
    final String bundledJson;
    final RulesetManifest bundled;
    try {
      bundledJson = await bundle.manifestJson();
      bundled = _parseManifest(bundledJson);
    } catch (e, st) {
      _log.error('failed to read the bundled rule-set MANIFEST', e, st);
      rethrow;
    }

    var state = await _readState();
    state = await _installStaged(bundled, state);
    await _deleteTmpFiles();

    final installed = await _readManifest(dir);
    final intact = installed != null && await allFilesMatch(dir, installed);
    final decision = chooseInstalled(
      bundled: bundled,
      installed: installed,
      installedIntact: intact,
      rejected: state.rejected.toSet(),
    );
    if (decision.choice == RulesetChoice.keepInstalled) {
      _log.debug('rule-sets kept (${decision.reason})');
      return false;
    }

    _log.info('extracting bundled rule-sets ${bundled.version}: ${decision.reason}');
    await _extractBundled(bundled, bundledJson);
    if (state.pending != null) await _writeState(state.withPending(null));
    _log.info('rule-sets extracted (${bundled.files.length} files, version ${bundled.version})');
    return true;
  });

  /// The manifest of the set on disk, or null when there is none or it is
  /// unreadable.
  Future<RulesetManifest?> installedManifest() => _readManifest(dir);

  Future<RulesetState> readState() => _locked(_readState);

  Future<void> recordCheck(DateTime at) => _locked(() async {
    await _writeState((await _readState()).withLastCheck(at));
  });

  /// A core start succeeded with the installed set: it is no longer pending.
  Future<void> confirmPending() => _locked(() async {
    final state = await _readState();
    if (state.pending == null) return;
    _log.info('rule-sets ${state.pending} confirmed by a core start');
    await _writeState(state.withPending(null));
  });

  /// Installs a set downloaded from the mirror. [changed] holds the bytes of
  /// every file whose digest differs from the installed copy; every other file
  /// listed in [manifest] must already be on disk with the listed digest.
  ///
  /// Refuses, changing nothing, a manifest that is not for this build (schema
  /// or file list), not newer than the installed one, rejected before, or
  /// whose bytes do not match it. On success the version is pending until a
  /// core start confirms it.
  Future<RulesetInstallResult> installDownloaded(RulesetManifest manifest, Map<String, List<int>> changed) =>
      _locked(() async {
        RulesetInstallResult refuse(String why) {
          _log.warning('rule-set download ${manifest.version} refused: $why');
          return RulesetInstallResult(RulesetInstallStatus.refused, why);
        }

        final bundled = _parseManifest(await bundle.manifestJson());
        final installed = await _readManifest(dir);
        final state = await _readState();

        if (manifest.schema != bundled.schema) {
          return refuse('schema ${manifest.schema}, this build loads ${bundled.schema}');
        }
        if (!_sameNames(manifest, bundled)) return refuse("file list differs from this build's");
        if (!manifest.fileNames.containsAll(changed.keys)) return refuse('bytes for a file the manifest does not list');
        final time = manifest.versionTime;
        if (time == null) return refuse('unreadable version');
        if (state.rejected.contains(manifest.version)) return refuse('version was rejected before');
        final installedTime = installed?.versionTime;
        if (installedTime != null && !time.isAfter(installedTime)) {
          return refuse('not newer than the installed ${installed!.version}');
        }

        for (final entry in manifest.files) {
          final bytes = changed[entry.name];
          if (bytes != null) {
            if (_digest(bytes) != entry.sha256.toLowerCase()) return refuse('${entry.name} does not match its digest');
          } else if (!await _fileMatches(File(p.join(dir.path, entry.name)), entry.sha256)) {
            return refuse('${entry.name} was not downloaded and the copy on disk is not the listed one');
          }
        }

        await dir.create(recursive: true);
        final written = <String>[];
        try {
          for (final MapEntry(key: name, value: bytes) in changed.entries) {
            final tmp = File(p.join(dir.path, '$name.tmp'));
            written.add(name);
            await tmp.writeAsBytes(bytes, flush: true);
            if (_digest(await tmp.readAsBytes()) != _digest(bytes)) {
              throw FileSystemException('read back differs from what was written', tmp.path);
            }
          }
        } on FileSystemException catch (e) {
          await _deleteTmpFor(written);
          return refuse('could not write ${e.path}: ${e.message}');
        }

        final refusedRename = <String>[];
        for (final name in changed.keys) {
          final tmp = File(p.join(dir.path, '$name.tmp'));
          if (!await _renameWithRetry(tmp, p.join(dir.path, name))) refusedRename.add(name);
        }
        if (refusedRename.isNotEmpty) {
          await _stage(manifest, changed);
          await _deleteTmpFor(changed.keys);
          _log.warning(
            'rule-sets ${manifest.version} staged for the next launch: '
            '${refusedRename.join(', ')} could not be replaced',
          );
          return RulesetInstallResult(RulesetInstallStatus.staged, '${refusedRename.length} files in use');
        }

        await _writeAtomically(File(p.join(dir.path, _manifestName)), jsonEncode(manifest.toJson()));
        await _writeState(state.withPending(manifest.version));
        _log.info('rule-sets ${manifest.version} installed (${changed.length} changed)');
        return RulesetInstallResult(RulesetInstallStatus.installed, '${changed.length} changed');
      });

  /// Puts the bundle back, after a core start failed with a downloaded set.
  /// [reject] is that set's version, so it is never installed again.
  Future<void> revertToBundled({String? reject}) => _locked(() async {
    final bundledJson = await bundle.manifestJson();
    final bundled = _parseManifest(bundledJson);
    _log.warning('reverting to the bundled rule-sets ${bundled.version}${reject == null ? '' : ', rejecting $reject'}');
    await _extractBundled(bundled, bundledJson);
    var state = (await _readState()).withPending(null);
    if (reject != null) state = state.withRejected(reject);
    await _writeState(state);
    await _deleteStaged();
  });

  /// True when every file the [manifest] lists is in [targetDir] and hashes to
  /// its digest.
  ///
  /// Reads every rule-set on each launch: about 0.9 MB for the ten files, a
  /// few milliseconds of hashing, and worth it. A truncated or half-written
  /// `.srs` that only an existence check would pass makes the core refuse to
  /// start, far from any sign of the cause.
  @visibleForTesting
  static Future<bool> allFilesMatch(Directory targetDir, RulesetManifest manifest) async {
    for (final file in manifest.files) {
      final onDisk = File(p.join(targetDir.path, file.name));
      try {
        if (!await onDisk.exists()) {
          _log.info('rule-set ${file.name} missing');
          return false;
        }
        // Log the name and the verdict, never the digests: a line full of hex
        // is unreadable in a bug report, and the name identifies the file.
        if (!await _fileMatches(onDisk, file.sha256)) {
          _log.warning('rule-set ${file.name} failed its checksum');
          return false;
        }
      } on FileSystemException catch (e) {
        _log.warning('rule-set ${file.name} unreadable: $e');
        return false;
      }
    }
    return true;
  }

  // --- internals, all called under the lock ---

  /// A download a Windows rename refused last session. Installed only when it
  /// is still for this build, newer than what is on disk, not rejected, and
  /// complete: its own files plus the unchanged files on disk match it.
  /// Either way the staged folder is gone afterwards.
  Future<RulesetState> _installStaged(RulesetManifest bundled, RulesetState state) async {
    if (!await stagedDir.exists()) return state;
    try {
      final staged = await _readManifest(stagedDir);
      final installed = await _readManifest(dir);
      final time = staged?.versionTime;
      final installedTime = installed?.versionTime;
      if (staged == null || time == null) return state;
      if (staged.schema != bundled.schema || !_sameNames(staged, bundled)) return state;
      if (state.rejected.contains(staged.version)) return state;
      if (installedTime != null && !time.isAfter(installedTime)) return state;

      final fromStaged = <String>[];
      for (final entry in staged.files) {
        final candidate = File(p.join(stagedDir.path, entry.name));
        if (await candidate.exists()) {
          if (!await _fileMatches(candidate, entry.sha256)) return state;
          fromStaged.add(entry.name);
        } else if (!await _fileMatches(File(p.join(dir.path, entry.name)), entry.sha256)) {
          return state;
        }
      }

      await dir.create(recursive: true);
      for (final name in fromStaged) {
        if (!await _renameWithRetry(File(p.join(stagedDir.path, name)), p.join(dir.path, name))) {
          _log.warning('staged rule-set $name could not be installed; the launch check will settle it');
          return state;
        }
      }
      await _writeAtomically(File(p.join(dir.path, _manifestName)), jsonEncode(staged.toJson()));
      final next = state.withPending(staged.version);
      await _writeState(next);
      _log.info('staged rule-sets ${staged.version} installed (${fromStaged.length} files)');
      return next;
    } catch (e, st) {
      _log.warning('staged rule-sets unusable, discarding', e, st);
      return state;
    } finally {
      await _deleteStaged();
    }
  }

  Future<void> _extractBundled(RulesetManifest bundled, String bundledJson) async {
    await dir.create(recursive: true);
    for (final file in bundled.files) {
      final tmp = File(p.join(dir.path, '${file.name}.tmp'));
      await tmp.writeAsBytes(await bundle.file(file.name), flush: true);
      if (!await _renameWithRetry(tmp, p.join(dir.path, file.name))) {
        throw FileSystemException('could not replace rule-set', p.join(dir.path, file.name));
      }
    }
    await _pruneStale(bundled);
    // Last, so a crash above leaves a MANIFEST the files disagree with, and
    // the next launch extracts again.
    await _writeAtomically(File(p.join(dir.path, _manifestName)), bundledJson);
  }

  /// Deletes `*.srs` files the bundle no longer lists. Without this a set
  /// dropped from the bundle lingers on upgraded installs forever.
  /// Best-effort: an unlisted file is never loaded by the core anyway.
  Future<void> _pruneStale(RulesetManifest manifest) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.endsWith('.srs') || manifest.fileNames.contains(name)) continue;
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

  /// Leftovers of a write interrupted by a crash. Best-effort.
  Future<void> _deleteTmpFiles() async {
    if (!await dir.exists()) return;
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.tmp')) await entity.delete();
      }
    } catch (e) {
      _log.debug('tmp cleanup: $e');
    }
  }

  Future<void> _deleteTmpFor(Iterable<String> names) async {
    for (final name in names) {
      try {
        final tmp = File(p.join(dir.path, '$name.tmp'));
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<void> _stage(RulesetManifest manifest, Map<String, List<int>> changed) async {
    await _deleteStaged();
    await stagedDir.create(recursive: true);
    for (final MapEntry(key: name, value: bytes) in changed.entries) {
      await File(p.join(stagedDir.path, name)).writeAsBytes(bytes, flush: true);
    }
    // Last: a staged folder without its MANIFEST is incomplete and discarded.
    await _writeAtomically(File(p.join(stagedDir.path, _manifestName)), jsonEncode(manifest.toJson()));
  }

  Future<void> _deleteStaged() async {
    try {
      if (await stagedDir.exists()) await stagedDir.delete(recursive: true);
    } catch (e) {
      _log.warning('could not delete staged rule-sets: $e');
    }
  }

  Future<bool> _renameWithRetry(File from, String to) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _rename(from, to);
        return true;
      } on FileSystemException catch (e) {
        if (attempt >= _renameRetries.length) {
          _log.warning('rename to ${p.basename(to)} refused: ${e.osError?.message ?? e.message}');
          return false;
        }
        await Future<void>.delayed(_renameRetries[attempt]);
      }
    }
  }

  static Future<void> _writeAtomically(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(target.path);
  }

  Future<RulesetState> _readState() async {
    try {
      if (!await _stateFile.exists()) return const RulesetState();
      return RulesetState.fromJson(jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>);
    } catch (e) {
      _log.warning('rule-set state unreadable, starting afresh: $e');
      return const RulesetState();
    }
  }

  Future<void> _writeState(RulesetState state) => _writeAtomically(_stateFile, jsonEncode(state.toJson()));

  static Future<RulesetManifest?> _readManifest(Directory from) async {
    final file = File(p.join(from.path, _manifestName));
    try {
      if (!await file.exists()) return null;
      return _parseManifest(await file.readAsString());
    } catch (e) {
      _log.warning('MANIFEST in ${p.basename(from.path)} unreadable: $e');
      return null;
    }
  }

  static RulesetManifest _parseManifest(String json) =>
      RulesetManifest.fromJson(jsonDecode(json) as Map<String, dynamic>);

  static Future<bool> _fileMatches(File file, String expected) async {
    try {
      if (!await file.exists()) return false;
      return _digest(await file.readAsBytes()) == expected.toLowerCase();
    } on FileSystemException {
      return false;
    }
  }

  static String _digest(List<int> bytes) => sha256.convert(bytes).toString();
}
