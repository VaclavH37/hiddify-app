import 'dart:io';

import 'package:path/path.dart' as p;

class ProfilePathResolver {
  const ProfilePathResolver(this._workingDir);

  final Directory _workingDir;

  Directory get directory => Directory(p.join(_workingDir.path, "configs"));

  /// The sealed config: `configs/<id>.enc`, AES-256-GCM under the per-install
  /// key (see `ProfileConfigCipher`). This is the only config the app writes.
  File encFile(String fileName) => File(p.join(directory.path, "$fileName.enc"));

  /// The pre-encryption plaintext location. Nothing writes here any more — it is
  /// kept solely so the one-time migration and profile deletion can find and
  /// remove files left by older installs.
  File legacyFile(String fileName) => File(p.join(directory.path, "$fileName.json"));

  /// Ditto for the download temp file older builds used. Subscription bodies are
  /// now fetched into memory and never touch disk.
  File legacyTempFile(String fileName) => legacyFile("$fileName.tmp");
}
