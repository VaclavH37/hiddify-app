import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'directories_provider.g.dart';

@Riverpod(keepAlive: true)
class AppDirectories extends _$AppDirectories with InfraLogger {
  final _methodChannel = const MethodChannel("com.raynlabs.app/platform");

  @override
  Future<Directories> build() async {
    final Directories dirs;
    if (kIsWeb) {
      return (baseDir: Directory("."), workingDir: Directory("."), tempDir: Directory("."));
    }
    if (PlatformUtils.isIOS) {
      final paths = await _methodChannel.invokeMethod<Map>("get_paths");
      loggy.debug("paths: $paths");
      dirs = (
        baseDir: Directory(paths?["base"]! as String),
        workingDir: Directory(paths?["working"]! as String),
        tempDir: Directory(paths?["temp"]! as String),
      );
    } else if (PlatformUtils.isWindows &&
        Environment.isPortable &&
        await checkDirectoryAccess(getPortableDirectory())) {
      final portableDir = getPortableDirectory();
      dirs = (baseDir: portableDir, workingDir: portableDir, tempDir: await getTemporaryDirectory());
    } else {
      // Android used to put workingDir on external storage
      // (/sdcard/Android/data/<pkg>/files), which put the sealed configs, the
      // core's LevelDB, the rule-sets and box.log somewhere `adb pull` and
      // Shizuku-privileged file managers can reach without root. Internal
      // app-private storage is root-only, so baseDir == workingDir on every
      // platform now. `_migrateAndroidWorkingDir` moves an upgraded install's
      // data across.
      final baseDir = await getApplicationSupportDirectory();
      final tempDir = await getTemporaryDirectory();
      if (Platform.isAndroid) await _migrateAndroidWorkingDir(baseDir);
      dirs = (baseDir: baseDir, workingDir: baseDir, tempDir: tempDir);
    }

    if (!dirs.baseDir.existsSync()) {
      await dirs.baseDir.create(recursive: true);
    }
    if (!dirs.workingDir.existsSync()) {
      await dirs.workingDir.create(recursive: true);
    }

    return dirs;
  }

  /// Moves an upgraded install's working data off external storage.
  ///
  /// Only `configs/` is carried across: it holds the sealed profile config, and
  /// losing it would force a subscription re-fetch (and break offline connect
  /// until one succeeded). Everything else is regenerated — rule-sets re-extract
  /// because the new directory has no MANIFEST, and the core rebuilds its
  /// LevelDB. The old tree is then deleted, which is the point of the exercise:
  /// leaving it behind would keep the very files this move exists to hide.
  ///
  /// Best-effort throughout. A failure here costs a re-fetch, not data, and must
  /// never stop the app from starting.
  static Future<void> _migrateAndroidWorkingDir(Directory target) async {
    try {
      final legacy = await getExternalStorageDirectory();
      if (legacy == null || !legacy.existsSync()) return;
      if (p.equals(legacy.path, target.path)) return;

      final legacyConfigs = Directory(p.join(legacy.path, 'configs'));
      if (legacyConfigs.existsSync()) {
        final targetConfigs = Directory(p.join(target.path, 'configs'));
        if (!targetConfigs.existsSync()) await targetConfigs.create(recursive: true);
        await for (final entity in legacyConfigs.list()) {
          if (entity is! File) continue;
          final dest = File(p.join(targetConfigs.path, p.basename(entity.path)));
          // Never clobber a config already written to the new location.
          if (dest.existsSync()) continue;
          try {
            await entity.copy(dest.path);
          } catch (_) {}
        }
      }

      await legacy.delete(recursive: true);
      Loggy('directories').info('migrated Android working dir off external storage');
    } catch (e) {
      Loggy('directories').warning('Android working-dir migration failed: ${e.runtimeType}');
    }
  }

  static Future<Directory> getDatabaseDirectory() async {
    if (kIsWeb) {
      return Directory(".");
    }
    if (PlatformUtils.isIOS || PlatformUtils.isMacOS) {
      return await getLibraryDirectory();
    } else if (PlatformUtils.isWindows &&
        Environment.isPortable &&
        await checkDirectoryAccess(getPortableDirectory())) {
      final portableDir = getPortableDirectory();
      return portableDir;
    } else if (PlatformUtils.isWindows || PlatformUtils.isLinux) {
      return await getApplicationSupportDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }

  static Directory getPortableDirectory() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    return Directory(p.join(exeDir.path, 'hiddify_portable_data'));
  }

  static Future<bool> checkDirectoryAccess(Directory dir) async {
    final testFile = File(p.join(dir.path, 'access_test.txt'));

    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      await testFile.writeAsString('Testing write permission...');
      await testFile.readAsString();
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
