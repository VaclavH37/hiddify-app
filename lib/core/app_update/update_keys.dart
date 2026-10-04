/// Public keys whose signatures the Windows updater accepts, by key id: base64
/// SEC1 uncompressed P-256 points (`0x04 || X || Y`, 65 bytes).
///
/// This map is the updater's trust root. A manifest signed by any other key is
/// discarded, whatever host served it.
///
/// - Generate a key with `dart run tool/publish_windows_update.dart keygen`
///   and paste the line it prints here. The private key stays in the
///   passphrase-protected file the tool writes, kept offline by the owner; it
///   never enters this repository or CI.
/// - Two slots allow rotation: ship the next key here first, wait until the
///   builds that lack it have aged out, then sign with it and retire the old
///   one. Removing a key strands every build that only trusts that key.
/// - Empty means no manifest verifies, so the updater offers nothing.
const kUpdatePublicKeys = <String, String>{
  'k1': 'BEBBfuu1umuOEFmjqvD/cu2uur7ETEoyYB9XfpoONh8OLWbIqEk4RwvZN03X16Bm8bG2Sg97/r0KlijoEduEDOY=',
};
