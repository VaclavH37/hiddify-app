import 'dart:io';

import 'package:hiddify/features/profile/model/config_slot.dart';
import 'package:path/path.dart' as p;

class ProfilePathResolver {
  const ProfilePathResolver(this._workingDir);

  final Directory _workingDir;

  Directory get directory => Directory(p.join(_workingDir.path, "configs"));

  /// The sealed config: `configs/<id>.enc`, AES-256-GCM under the per-install
  /// key (see `ProfileConfigCipher`). This is the only config the app writes.
  File encFile(String fileName) => File(p.join(directory.path, "$fileName.enc"));

  /// The sealed config for one slot: `configs/<id>.enc` for the primary,
  /// `configs/<id>.standby.enc` for the precached standby-hub config.
  ///
  /// Goes through [configSlotStorageId] rather than interpolating the suffix
  /// here, so the file name can never drift from the AAD the blob is sealed
  /// under — the native readers derive that AAD from this very name.
  File encFileForSlot(String fileName, ConfigSlot slot) => encFile(configSlotStorageId(fileName, slot));

  /// The pre-encryption plaintext location. Nothing writes here any more — it is
  /// kept solely so the one-time migration and profile deletion can find and
  /// remove files left by older installs.
  File legacyFile(String fileName) => File(p.join(directory.path, "$fileName.json"));

  /// Ditto for the download temp file older builds used. Subscription bodies are
  /// now fetched into memory and never touch disk.
  File legacyTempFile(String fileName) => legacyFile("$fileName.tmp");
}
