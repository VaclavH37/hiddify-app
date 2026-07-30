import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hiddify/features/profile/data/config_key_store.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
// Targeted imports, not `export.dart` — the umbrella also exports a `Digest`,
// which collides with `package:crypto`'s. Same reasoning as rayn_token.dart.
import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;
import 'package:pointycastle/block/aes.dart' show AESEngine;
import 'package:pointycastle/block/modes/gcm.dart' show GCMBlockCipher;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_config_cipher.g.dart';

/// Why a stored config blob could not be opened. Carried for LOGS ONLY — the
/// plaintext is the user's sing-box config (hub IP, per-user UUIDs, Reality
/// shortIDs), so failures are reported by reason and there is deliberately no
/// string a config could ever be interpolated into.
enum ConfigCipherRejection {
  /// The per-install key is missing or unreadable: first run before the key was
  /// created, a wiped/rotated platform keystore, a restored-to-new-device
  /// install, or a portable Windows install moved to another user (DPAPI is
  /// user-bound).
  keyUnavailable,

  /// Shorter than `version(1) + nonce(12) + tag(16)`.
  tooShort,

  /// Version byte this build has no handler for — i.e. the file was written by a
  /// newer build and the user downgraded.
  unsupportedVersion,

  /// GCM tag check failed: wrong key, wrong profile id (the AAD), truncation, or
  /// tampering.
  authFailed,

  /// Opened, but the plaintext is not valid UTF-8.
  notUtf8,
}

/// Outcome of opening a stored config.
///
/// Unlike [RaynLinkResult] there is no separate "unsupported version" case: for
/// a file we wrote ourselves every failure has the *same* remedy — discard the
/// blob and re-fetch the subscription — so splitting the type would buy the
/// caller nothing. The distinction survives in [ConfigCipherRejection] for logs.
sealed class ConfigDecryptResult {
  const ConfigDecryptResult();
}

/// Opened successfully. [json] is the normalised sing-box config — never log it.
final class ConfigDecryptOk extends ConfigDecryptResult {
  const ConfigDecryptOk(this.json);

  final String json;
}

final class ConfigDecryptFailed extends ConfigDecryptResult {
  const ConfigDecryptFailed(this.reason);

  final ConfigCipherRejection reason;
}

/// Thrown by [ProfileConfigCipher.encrypt] when the config cannot be sealed.
///
/// Encrypt failures are asymmetric with decrypt failures on purpose: a decrypt
/// failure is an expected, recoverable state that drives the re-fetch path, so
/// it is a value. Failing to *write* means we are about to persist nothing at
/// all, which must abort the surrounding profile transaction — and every write
/// path already runs inside `TaskEither.tryCatch`.
class ConfigCipherException implements Exception {
  const ConfigCipherException(this.reason);

  final ConfigCipherRejection reason;

  @override
  String toString() => 'ConfigCipherException(${reason.name})';
}

/// Seals the sing-box profile config for storage at `configs/<id>.enc`.
///
/// Wire format (raw bytes on disk, no base64 — there is no transport to encode
/// for):
///
///     version(1) = 0x01 || nonce(12) || ciphertext || tag(16)
///     AAD        = utf8(profileId)
///
/// AES-256-GCM, 128-bit tag, CSPRNG nonce per write, under a 32-byte per-install
/// key held in the platform keystore (see [ConfigKeyStore]).
///
/// Unlike the `rayn://` cryptolink envelope this one binds the AAD to the
/// profile id, so a blob cannot be swapped between profiles. The cryptolink
/// envelope is required to use an empty AAD by its wire contract; here we own
/// both ends, so we take the integrity for free.
///
/// Threat model, stated honestly: this removes the "open it in Notepad / adb
/// pull it" path and nothing more. The plaintext must exist in the core's
/// memory while the tunnel is up, and the subscription URL that regenerates
/// this config is a separate secret handled elsewhere. A debugger defeats this.
class ProfileConfigCipher {
  const ProfileConfigCipher(this._keyStore);

  final ConfigKeyStore _keyStore;

  static const configVersionV1 = 0x01;
  static const _nonceLen = 12;
  static const _tagLen = 16;
  static const _minBlobLen = 1 + _nonceLen + _tagLen;

  static final _random = Random.secure();

  /// Seals [json] for [profileId]. Throws [ConfigCipherException] if the
  /// per-install key is unavailable.
  Future<Uint8List> encrypt({required String profileId, required String json}) async {
    final key = await _keyStore.get();
    if (key == null) {
      throw const ConfigCipherException(ConfigCipherRejection.keyUnavailable);
    }

    final nonce = Uint8List.fromList(List<int>.generate(_nonceLen, (_) => _random.nextInt(256)));

    // GCMBlockCipher is stateful — construct per call, never cache.
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), _tagLen * 8, nonce, _aad(profileId)),
      );
    // PointyCastle emits ciphertext||tag concatenated, which is precisely our
    // layout — do NOT split the trailing tag off.
    final ctAndTag = cipher.process(Uint8List.fromList(utf8.encode(json)));

    final out = Uint8List(1 + _nonceLen + ctAndTag.length)
      ..[0] = configVersionV1
      ..setRange(1, 1 + _nonceLen, nonce)
      ..setRange(1 + _nonceLen, 1 + _nonceLen + ctAndTag.length, ctAndTag);
    return out;
  }

  /// Opens a stored blob. Never throws — the caller decides whether an
  /// unopenable config means "re-fetch" or "tell the user to go online".
  Future<ConfigDecryptResult> decrypt({required String profileId, required Uint8List blob}) async {
    final key = await _keyStore.get();
    if (key == null) {
      return const ConfigDecryptFailed(ConfigCipherRejection.keyUnavailable);
    }
    if (blob.length < _minBlobLen) {
      return const ConfigDecryptFailed(ConfigCipherRejection.tooShort);
    }

    // A switch, not `if (v != 0x01) reject`, so a future envelope change ships
    // as one extra arm here and old blobs stay readable through the transition.
    return switch (blob[0]) {
      == configVersionV1 => _openV1(profileId, blob, key),
      _ => const ConfigDecryptFailed(ConfigCipherRejection.unsupportedVersion),
    };
  }

  ConfigDecryptResult _openV1(String profileId, Uint8List blob, Uint8List key) {
    // Copies, not sublistView: PointyCastle internals reach for
    // `.buffer.asUint8List()` in places and lose a non-zero offsetInBytes. The
    // resulting bug looks exactly like a wrong key, so pay the copy.
    final nonce = blob.sublist(1, 1 + _nonceLen);
    final ctAndTag = blob.sublist(1 + _nonceLen);

    final Uint8List plain;
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), _tagLen * 8, nonce, _aad(profileId)),
        );
      plain = cipher.process(ctAndTag);
    } catch (_) {
      // Tag check failed. `plain` is unassigned on this path, so no partial
      // plaintext can escape.
      return const ConfigDecryptFailed(ConfigCipherRejection.authFailed);
    }

    try {
      return ConfigDecryptOk(utf8.decode(plain));
    } catch (_) {
      return const ConfigDecryptFailed(ConfigCipherRejection.notUtf8);
    }
  }

  /// The AAD is the profile id's UTF-8 bytes. Kotlin and Swift must produce the
  /// same bytes — profile ids are UUIDv4 strings, so this is ASCII in practice.
  static Uint8List _aad(String profileId) => Uint8List.fromList(utf8.encode(profileId));
}

@Riverpod(keepAlive: true)
ProfileConfigCipher profileConfigCipher(Ref ref) => ProfileConfigCipher(ref.watch(configKeyStoreProvider));
