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
    // Mode 1 is the foreground core in the app process, since the local channel
    // was authenticated. It was mode 3 before that, and this list named only
    // stderr3 — so the export silently omitted the one file worth reading while
    // still looking like it had worked. Both stay: an install that has not been
    // through a secure-mode start yet still has the old file.
    'data/stderr1.log',
    'data/stderr3.log',
    // Android's Kotlin calls Libbox.redirectStderr AGAIN after Mobile.setup, and
    // the second call wins — so on Android the core's output lands here, in the
    // working-directory root, rather than in data/. Named for a mode it no
    // longer corresponds to (MethodHandler.kt), and left that way because
    // renaming it would only move the confusion.
    'stderr2.log',
    // Android's `:bg` service, same override (BoxService.kt).
    'stderr.log',
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

  /// The same logs as one block of text, for the clipboard.
  ///
  /// A fallback for when the share sheet refuses. `Share.shareXFiles` goes
  /// through a native plugin and a UIActivityViewController, and when that throws
  /// there is nothing to debug from the Dart side and no second route off the
  /// device — which is the position this class exists to prevent. The clipboard
  /// needs no file URLs, no activity controller and no reader with access to the
  /// App Group container, so it fails in far fewer ways.
  ///
  /// Tail-truncated per file, because `box.log` reaches tens of megabytes and a
  /// clipboard that large is not pasteable. The tail is the useful half: a
  /// failure is at the end, not the start. Truncation is announced in-band so a
  /// short paste is never mistaken for a short log.
  String asText({int maxBytesPerFile = 40 * 1024}) {
    final buffer = StringBuffer();
    for (final file in collect()) {
      final name = p.relative(file.path, from: workingDir.path);
      String body;
      try {
        final bytes = file.readAsBytesSync();
        if (bytes.length > maxBytesPerFile) {
          body = '[truncated: showing the last $maxBytesPerFile of ${bytes.length} bytes]\n'
              '${String.fromCharCodes(bytes.sublist(bytes.length - maxBytesPerFile))}';
        } else {
          body = String.fromCharCodes(bytes);
        }
      } on FileSystemException catch (e) {
        // By reason, never by value: this runs over a directory that also holds
        // the sealed config, and an exception can carry a path.
        body = '[unreadable: ${e.osError?.errorCode ?? 'unknown'}]';
      }
      buffer
        ..writeln('===== $name =====')
        ..writeln(body)
        ..writeln();
    }
    return buffer.toString();
  }
}
