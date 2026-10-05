import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:path/path.dart' as p;

/// Where the installer is downloaded: `updates\` beside the running
/// executable, i.e. `C:\Program Files\RaynVPN\updates`.
///
/// Under Program Files only an administrator can write. The app runs elevated
/// and starts the installer elevated, so a folder any user process could write
/// (%TEMP%, %LOCALAPPDATA%) would let it swap the file between the check and
/// the launch and run its own code as administrator.
Directory updatesDirectory([String? executable]) =>
    Directory(p.join(p.dirname(executable ?? Platform.resolvedExecutable), 'updates'));

/// The installer's file name: the last part of its manifest path, which the
/// manifest parser has already limited to `[A-Za-z0-9._-]+\.exe`.
String installerFileName(UpdateInstaller installer) => p.posix.basename(installer.path);

/// The Inno Setup log of the last update, kept for a failed install.
const updateLogName = 'install.log';

/// Why [file] is not the installer [expected] describes, or null when it is.
/// Read back from disk right before the launch, so what runs is what was
/// checked.
Future<String?> installerProblem(File file, UpdateInstaller expected) async {
  final length = await file.length();
  if (length != expected.size) return '$length bytes, expected ${expected.size}';
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != expected.sha256) return 'does not match its digest';
  return null;
}

/// How the app starts the installer (see `windows/packaging/exe/inno_setup.sas`):
/// silent with Inno's own progress window, no questions, no reboot, and the
/// two switches that make it start the new build afterwards (`--updated`,
/// plus `--reconnect` when the app was connected).
List<String> installerArguments({required bool reconnect, required String logPath}) => [
  '/SILENT',
  '/SUPPRESSMSGBOXES',
  '/NORESTART',
  '/RAYNUPDATE=1',
  '/RAYNRECONNECT=${reconnect ? 1 : 0}',
  '/LOG=$logPath',
];

/// Deletes downloaded installers and partial downloads from [dir], keeping the
/// install log. A file still in use (the setup that just ran can outlive the
/// relaunch by a few seconds) is left for the next call. Returns how many
/// files are left over.
int clearUpdatesFolder(Directory dir) {
  if (!dir.existsSync()) return 0;
  var left = 0;
  for (final entity in dir.listSync()) {
    if (entity is! File || p.basename(entity.path) == updateLogName) continue;
    try {
      entity.deleteSync();
    } on FileSystemException {
      left++;
    }
  }
  return left;
}

/// What the installer passed when it started this build.
class UpdateLaunch {
  const UpdateLaunch({this.updated = false, this.reconnect = false});

  factory UpdateLaunch.parse(List<String> args) =>
      UpdateLaunch(updated: args.contains('--updated'), reconnect: args.contains('--reconnect'));

  final bool updated;
  final bool reconnect;
}

enum UpdateAttemptOutcome {
  /// No update was attempted, or it is already settled.
  none,

  /// This is the build the update installed.
  installed,

  /// An update was started, and this is still an older build: the install
  /// was cancelled or failed.
  notInstalled,
}

/// Settles the update the last run started, if any. [attemptBuild] is the
/// build it was installing; [updated] is the installer's `--updated` flag,
/// which also counts when the attempt record is missing.
UpdateAttemptOutcome settleUpdateAttempt({int? attemptBuild, required int currentBuild, required bool updated}) {
  if (attemptBuild == null) return updated ? UpdateAttemptOutcome.installed : UpdateAttemptOutcome.none;
  return currentBuild >= attemptBuild ? UpdateAttemptOutcome.installed : UpdateAttemptOutcome.notInstalled;
}
