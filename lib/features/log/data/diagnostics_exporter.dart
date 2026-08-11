import 'dart:io';

import 'package:path/path.dart' as p;

/// Collects the on-disk log files so the user can hand them to the share sheet.
///
/// This exists because on iOS there is otherwise **no way to read them at all**.
/// The tunnel runs in a Network Extension — a separate process the system can
/// start with the app closed — and everything it writes lands in the App Group
/// container, reachable only from a Mac with the device physically attached
/// (Xcode → Devices and Simulators → Download Container). A cloud build host
/// cannot do that, and this fork has no in-app log viewer, so without this the
/// only diagnosis available on iOS is whatever reaches `CoreAlert` and surfaces
/// in the UI. That covers "no stored configuration" and a failed service start;
/// it does not cover a tunnel that comes up and then quietly routes nothing.
///
/// Android is no better placed — the working directory is internal storage, so
/// reading it needs adb or root.
///
/// **The file list is an allowlist, and that is the point.** The same working
/// directory holds `configs/<id>.enc`, the extracted rule-sets and the core's
/// LevelDB. A glob over `*.log`, or anything that walks the tree, would
/// eventually sweep one of those into a share sheet — which is precisely what
/// sealing the config at rest exists to prevent. Nothing goes in this list that
/// is not a log.
class DiagnosticsExporter {
  const DiagnosticsExporter(this.workingDir);

  final Directory workingDir;

  /// Paths relative to the working directory, ordered most-useful-first — this is
  /// the order they reach the share sheet.
  ///
  /// Every entry is a log written by us or by the core. Do not add a path here
  /// without checking what can end up inside it.
  static const logFiles = <String>[
    // Written by the Swift (`ExtensionProvider.writeMessage`), not the core, so
    // it survives the core failing to start at all — which is exactly the case
    // you need it for.
    'network_extension_error.log',
    // hcore redirects stderr per setup mode (`v2/hcore/grpc_server.go`). Mode 4
    // is the background core: the iOS packet-tunnel extension, Android's `:bg`.
    'data/stderr4.log',
    // Mode 3 is the foreground core, in the app process.
    'data/stderr3.log',
    // Loggy's own file. Always written on desktop; on mobile only when the core
    // debug flag is on.
    'app.log',
    // The core's own log file. Debug builds only — release passes an empty
    // `logFile` path, so the core writes nothing.
    'data/box.log',
  ];

  /// The subset of [logFiles] that exists and has content, as absolute paths.
  ///
  /// Missing entries are the normal case rather than an error: `box.log` never
  /// exists in a release build, `stderr3.log` only after the app has started a
  /// foreground core, and `network_extension_error.log` only on iOS. Empty files
  /// are skipped too — a zero-byte log in a share sheet is worse than an absent
  /// one, because it looks like an answer.
  List<File> collect() {
    final found = <File>[];
    for (final relative in logFiles) {
      final file = File(p.joinAll([workingDir.path, ...p.posix.split(relative)]));
      if (!file.existsSync()) continue;
      try {
        if (file.lengthSync() == 0) continue;
      } on FileSystemException {
        // Unreadable is the same as absent for our purposes; never let one bad
        // file stop the export of the others.
        continue;
      }
      found.add(file);
    }
    return found;
  }
}
