import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/utils/rayn_link_key.dart';
import 'package:loggy/loggy.dart';
// Targeted imports, not `export.dart` — the umbrella also exports a `Digest`,
// which collides with `package:crypto`'s.
import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;
import 'package:pointycastle/block/aes.dart' show AESEngine;
import 'package:pointycastle/block/modes/gcm.dart' show GCMBlockCipher;

/// Why a `rayn://import/<token>` link was rejected. Carried for LOGS ONLY —
/// never rendered to a user, and deliberately an enum so there is no string a
/// decrypted URL could ever be interpolated into (see
/// RAYN-LINK-SYMMETRIC-MIGRATION.md §9: log failures by reason, never by value).
enum RaynLinkRejection {
  /// Not a `rayn://import/…` URI at all — wrong scheme, host, or unparseable.
  notARaynLink,
  empty,
  badBase64,

  /// Shorter than `version(1) + nonce(12) + tag(16)`.
  tooShort,

  /// GCM tag check failed: wrong key, or the blob was tampered with/truncated.
  authFailed,
  notUtf8,

  /// Decrypted cleanly but the plaintext isn't an `https://` URL.
  notHttps,

  /// The embedded key material could not be reconstructed — a broken build.
  keyUnavailable,
}

/// Outcome of parsing/decrypting a cryptolink. Three cases, because
/// "this app is too old to read this link" and "this link is broken" need
/// different words in front of the user (§10).
sealed class RaynLinkResult {
  const RaynLinkResult();
}

/// Decrypted successfully. [url] is the plain `https://` subscription URL —
/// it is the user's subscription credential, so never log it (§9).
final class RaynLinkOk extends RaynLinkResult {
  const RaynLinkOk(this.url);

  final String url;
}

/// Malformed, tampered, wrong key, or not a rayn link.
/// UX: "This link is invalid or has expired. Please copy it again."
final class RaynLinkInvalid extends RaynLinkResult {
  const RaynLinkInvalid(this.reason);

  final RaynLinkRejection reason;
}

/// The envelope's version byte is one this build has no handler for.
/// UX: "please update the app" — explicitly NOT "invalid link" (§10).
final class RaynLinkUnsupportedVersion extends RaynLinkResult {
  const RaynLinkUnsupportedVersion(this.version);

  final int version;
}

/// Decrypts `rayn://import/<base64url(blob)>` cryptolinks.
///
/// Wire format (RAYN-LINK-SYMMETRIC-MIGRATION.md §4):
/// `version(1) || nonce(12) || ciphertext || tag(16)`, base64url with no
/// padding, AES-256-GCM under `SHA-256(utf8(RAYN_LINK_SECRET))`, empty AAD.
///
/// This is an OBFUSCATION layer, not a secret store — the shared secret ships in
/// every published binary and is public by construction. The integrity boundary
/// is TLS in transit plus the `https://` plaintext check below, never key
/// secrecy. Anyone holding the key can also *forge* a link, so nothing may trust
/// a link's contents beyond "it names a host we will then reach over TLS".
abstract class RaynTokenDecryptor {
  static const _linkVersionV2 = 0x02;
  static const _nonceLen = 12;
  static const _tagLen = 16;
  static const _minBlobLen = 1 + _nonceLen + _tagLen;

  // Neutral channel name, and every message below is wrapped in `kDebugMode`.
  // `--obfuscate` renames symbols but does NOT touch string literals, so a
  // descriptive log line inside this class would be a `strings`-greppable
  // signpost pointing straight at the key derivation — undoing the masking in
  // rayn_link_key.dart. `kDebugMode` is a const, so these branches (and their
  // literals) are dead-code-eliminated out of release AOT entirely, while debug
  // builds keep the full diagnostics.
  static final _log = Loggy('import');

  /// `key = SHA-256` of the secret STRING's UTF-8 bytes.
  ///
  /// §6.3, the most common porting mistake: the secret is produced by
  /// `openssl rand -hex 32` so it LOOKS like hex. Hash those 64 ASCII
  /// characters — do NOT hex-decode to 32 bytes and hash those.
  static Uint8List deriveKey(String secret) => Uint8List.fromList(sha256.convert(utf8.encode(secret)).bytes);

  static Uint8List? _testKey;
  static bool _testKeySet = false;

  /// Test seam. Once called (including with null) the embedded key is bypassed
  /// for the rest of the isolate, so a test can pin the "no key" state.
  @visibleForTesting
  static void debugSetKey(Uint8List? key) {
    _testKey = key;
    _testKeySet = true;
  }

  @visibleForTesting
  static void debugClearKeyOverride() {
    _testKey = null;
    _testKeySet = false;
  }

  static Uint8List? _key() {
    // Always hand back a fresh buffer: _openV2 scrubs the key it was given, and
    // an injected test key must survive more than one decrypt.
    if (_testKeySet) {
      final key = _testKey;
      return key == null ? null : Uint8List.fromList(key);
    }
    try {
      final key = raynLinkKey();
      if (key.length != 32) {
        if (kDebugMode) _log.error('link key is ${key.length} bytes, expected 32 — broken build');
        return null;
      }
      return key;
    } catch (e) {
      // Never log `e` itself; it could carry key material.
      if (kDebugMode) _log.error('link key unavailable (${e.runtimeType})');
      return null;
    }
  }

  static bool get isLoaded => _key() != null;

  /// Bootstrap warm-up: surfaces a broken key table at startup instead of at
  /// first import.
  ///
  /// MUST NOT throw. `bootstrap.dart`'s `_init` rethrows, so a throw here would
  /// hard-crash app startup. The key is resolved lazily inside [decrypt]
  /// anyway, so this is diagnostics only — a link that arrives before this runs
  /// (cold-start deep link) still decrypts fine.
  static Future<void> load() async {
    final ok = _key() != null;
    if (kDebugMode) {
      if (!ok) {
        _log.error('link key could not be reconstructed — import will fail');
      } else if (kRaynLinkKeyIsDev) {
        _log.warning('link key is the DEVELOPMENT key (id $kRaynLinkKeyId) — not shippable');
      } else {
        _log.info('link key id $kRaynLinkKeyId');
      }
    }
  }

  /// Decrypts [tokenSegment] — the part after `rayn://import/`.
  ///
  /// Never throws, never returns partially-decrypted output. Input arrives from
  /// QR scans and clipboard paste, so assume arbitrary bytes (§10).
  static RaynLinkResult decrypt(String tokenSegment) {
    final key = _key();
    if (key == null) return const RaynLinkInvalid(RaynLinkRejection.keyUnavailable);

    final trimmed = tokenSegment.trim();
    if (trimmed.isEmpty) return const RaynLinkInvalid(RaynLinkRejection.empty);

    final Uint8List blob;
    try {
      blob = base64Url.decode(_padBase64Url(trimmed));
    } catch (_) {
      return const RaynLinkInvalid(RaynLinkRejection.badBase64);
    }

    if (blob.length < _minBlobLen) {
      return const RaynLinkInvalid(RaynLinkRejection.tooShort);
    }

    // A switch, not `if (v != 0x02) reject` — §11. A future envelope change ships
    // as one extra arm here first, the backend flips once that build has adoption,
    // and a later release drops the old arm. That sequence avoids a forced-update
    // event; the reverse order (what the old RSA runbook described) would break
    // every user at once.
    try {
      return switch (blob[0]) {
        == _linkVersionV2 => _openV2(blob, key),
        final version => RaynLinkUnsupportedVersion(version),
      };
    } finally {
      // Best-effort scrub on every path. Dart guarantees no zeroing (the GC may
      // already have copied), so this is hygiene, not a control.
      key.fillRange(0, key.length, 0);
    }
  }

  static RaynLinkResult _openV2(Uint8List blob, Uint8List key) {
    // Copies, not sublistView: PointyCastle internals reach for
    // `.buffer.asUint8List()` in places and lose a non-zero offsetInBytes. The
    // resulting bug looks exactly like a wrong key (§6.2), so pay the <1KB copy.
    final nonce = blob.sublist(1, 1 + _nonceLen);
    // PointyCastle expects ciphertext||tag concatenated, which is precisely our
    // layout — do NOT split the trailing tag off.
    final ctAndTag = blob.sublist(1 + _nonceLen);

    final Uint8List plain;
    try {
      // GCMBlockCipher is stateful — construct per call, never cache.
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(key),
            _tagLen * 8,
            nonce,
            Uint8List(0), // empty AAD — must stay empty (§4)
          ),
        );
      plain = cipher.process(ctAndTag);
    } catch (_) {
      // Tag check failed. `plain` is unassigned on this path, so no partial
      // plaintext can escape.
      return const RaynLinkInvalid(RaynLinkRejection.authFailed);
    }

    final String url;
    try {
      url = utf8.decode(plain);
    } catch (_) {
      return const RaynLinkInvalid(RaynLinkRejection.notUtf8);
    }

    // The envelope carries no authenticity (the key is public by construction),
    // so this check plus TLS is the integrity boundary. Keep it.
    if (!url.startsWith('https://')) {
      return const RaynLinkInvalid(RaynLinkRejection.notHttps);
    }
    return RaynLinkOk(url);
  }

  /// Go emits `base64.RawURLEncoding` (no `=`); Dart's decoder is strict (§6.1).
  static String _padBase64Url(String input) {
    final mod = input.length % 4;
    return mod == 0 ? input : input + ('=' * (4 - mod));
  }
}
