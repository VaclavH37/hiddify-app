import 'dart:io';

import 'package:hiddify/features/profile/data/profile_config_cipher.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

/// One-time cleanup of the plaintext artefacts earlier builds left on disk.
///
/// Two of them:
///
/// * `configs/<id>.json` — the normalised sing-box config the Go core used to
///   write when handed a `configPath`. Sealed in place to `<id>.enc` so the
///   user keeps offline connect through the upgrade, then deleted.
/// * `data/current-config.json` — the fully built config, including our routing
///   and DNS design. Never read by anything; the core no longer writes it, but
///   an upgraded install still has the last one.
///
/// Also sweeps `configs/*.tmp.json` and the `*.tmp.json.<n>` fragments the old
/// line-list expansion created and never cleaned up.
///
/// Everything here is best-effort. The config is re-derivable from the
/// subscription, so a failure costs a refresh, not data.
///
/// Deleting a file does not scrub the underlying blocks on an SSD. This closes
/// the "open it in a text editor" path, not forensic recovery.
class ConfigAtRestMigration {
  const ConfigAtRestMigration({required this.pathResolver, required this.cipher, required this.workingDir});

  final ProfilePathResolver pathResolver;
  final ProfileConfigCipher cipher;
  final Directory workingDir;

  static final _log = Loggy('config_migration');

  Future<void> run() async {
    await _sealLegacyConfigs();
    await _deleteStaleArtefacts();
  }

  Future<void> _sealLegacyConfigs() async {
    final dir = pathResolver.directory;
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.json') || name.endsWith('.tmp.json')) continue;

      final id = name.substring(0, name.length - '.json'.length);
      final sealed = pathResolver.encFile(id);
      try {
        if (await sealed.exists()) {
          // Already migrated on an earlier launch; the plaintext is just residue.
          await entity.delete();
          continue;
        }
        final blob = await cipher.encrypt(profileId: id, json: await entity.readAsString());
        await sealed.writeAsBytes(blob, flush: true);
        // Only ever delete the plaintext once its replacement is on disk.
        await entity.delete();
        _log.info('sealed legacy config for [$id]');
      } catch (e) {
        // Includes ConfigCipherException when the keystore is unavailable. The
        // profile simply re-fetches on next refresh.
        _log.warning('could not seal legacy config for [$id]: ${e.runtimeType}');
      }
    }
  }

  Future<void> _deleteStaleArtefacts() async {
    // `current-config.json` is the artefact the core used to write on every
    // start. The two `debug-*` names are written only by a debug app build and a
    // `raynconfigdump` core respectively — neither can occur in a shipped build,
    // but an install that was once a debug build would otherwise keep the
    // plaintext forever after moving to release.
    //
    // The two `goroutine-*.log` files are the same class of leftover, with one
    // difference that makes sweeping them necessary rather than merely tidy: they
    // USED to be written by shipped builds. `-start` on any launch where the user
    // had enabled Debug mode or picked log level debug/trace; `-stop` on any failed
    // service stop, with no user action and no gate at all. Both are now behind the
    // `raynconfigdump` build tag, which stops new ones — only this removes the ones
    // already on disk. They are full goroutine dumps, so they name sing-box and
    // hiddify-core in cleartext.
    for (final name in const [
      'current-config.json',
      'debug-profile-config.json',
      'debug-built-config.json',
      'goroutine-start.log',
      'goroutine-stop.log',
    ]) {
      await _deleteIfPresent(File(p.join(workingDir.path, 'data', name)));
    }

    final dir = pathResolver.directory;
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // `<id>.tmp.json` and the `<id>.tmp.json.<n>` expansion fragments.
      if (name.contains('.tmp.json')) await _deleteIfPresent(entity);
    }
  }

  Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
        _log.info('removed stale plaintext ${p.basename(file.path)}');
      }
    } catch (e) {
      _log.warning('could not remove ${p.basename(file.path)}: ${e.runtimeType}');
    }
  }
}
