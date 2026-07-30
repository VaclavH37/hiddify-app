import 'dart:typed_data';

import 'package:crypto/crypto.dart';

part 'rayn_link_key_data.dart';

/// The AES-256-GCM key for `rayn://import/<token>` cryptolinks:
/// `SHA-256(utf8(RAYN_LINK_SECRET))`, per RAYN-LINK-SYMMETRIC-MIGRATION.md §4.
///
/// The key is never stored — neither is the secret it derives from. It is
/// recomputed here from two build-time-randomised tables (see
/// `tool/gen_rayn_link_key.dart`, which must stay byte-for-byte inverse to this).
///
/// Deliberately **not** cached: recomputation costs one SHA-256 over 16 bytes
/// plus 96 XORs, and holding the key in a static field would make it dumpable
/// at any moment rather than only during a decrypt.
///
/// This is an OBFUSCATION layer, not a secret store. The key is public by
/// construction — it ships in every published binary. It buys distance from
/// `strings`/apktool, not secrecy; nothing security-bearing may rest on it.
/// See RAYN-LINK-SYMMETRIC-MIGRATION.md §2.
Uint8List raynLinkKey() {
  final r = _t1[0] & 0x3F;
  final b = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    b[i] = _t0[(i + r) & 0x3F];
  }

  final s = sha256.convert(_t1).bytes;
  final key = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    key[i] = b[2 * i] ^ b[2 * i + 1] ^ s[i] ^ (i & 0xFF);
  }

  // Best-effort: shrink the window in which the un-combined material sits in
  // the heap. Dart makes no zeroing guarantee (the GC may already have copied),
  // so treat this as hygiene, not a control.
  b.fillRange(0, b.length, 0);
  return key;
}
