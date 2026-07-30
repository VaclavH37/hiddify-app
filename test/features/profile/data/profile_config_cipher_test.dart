// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/config_key_store.dart';
import 'package:hiddify/features/profile/data/profile_config_cipher.dart';
import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;
import 'package:pointycastle/block/aes.dart' show AESEngine;
import 'package:pointycastle/block/modes/gcm.dart' show GCMBlockCipher;

/// The conformance vector. Produced by an INDEPENDENT implementation — Go's
/// `crypto/cipher` GCM — so this test proves the Dart envelope matches the wire
/// format rather than merely matching itself. Kotlin (`:bg`) and Swift (the
/// Network Extension) must decrypt this same blob to the same plaintext; those
/// are the only other readers, and this is what stops the three implementations
/// silently drifting apart.
///
/// Generated with:
///   gcm.Seal(nil, nonce, []byte(plaintext), []byte(profileId))
///   blob = 0x01 || nonce || ctAndTag
const _vectorKeyHex = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
const _vectorProfileId = '6f9619ff-8b86-d011-b42d-00c04fc964ff';
const _vectorPlaintext = '{"outbounds":[{"tag":"conformance","type":"vless"}]}';
const _vectorBlobHex =
    '01a1b2c3d4e5f60718293a4b5c79040e8ceb5008bdda614aa40c2f2722b3bac4'
    'fc186a28bec71c6cf161a58f5e5c9ee0a01476345a1960706a8fb6fcc61a9ae0'
    '1efc77dc85e9361c16d47767f071e24308';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

ProfileConfigCipher _cipherWith(Uint8List? key) =>
    ProfileConfigCipher(ConfigKeyStore()..debugSetKey(key));

/// Seals arbitrary bytes into the envelope, bypassing [ProfileConfigCipher.encrypt].
/// Only needed to manufacture plaintexts our own writer can never produce.
Uint8List _sealRaw(Uint8List key, String profileId, Uint8List plaintext) {
  const nonce = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(key),
        128,
        Uint8List.fromList(nonce),
        Uint8List.fromList(utf8.encode(profileId)),
      ),
    );
  final ctAndTag = cipher.process(plaintext);
  return Uint8List.fromList([ProfileConfigCipher.configVersionV1, ...nonce, ...ctAndTag]);
}

void main() {
  const profileId = 'a3f1c2d4-0000-4000-8000-abcdefabcdef';
  final key = Uint8List.fromList(List<int>.generate(32, (i) => (i * 7 + 3) & 0xFF));

  group('conformance vector (§ cross-language)', () {
    test('decrypts the Go-generated blob to the exact plaintext', () async {
      final cipher = _cipherWith(_hex(_vectorKeyHex));
      final result = await cipher.decrypt(
        profileId: _vectorProfileId,
        blob: _hex(_vectorBlobHex),
      );
      expect(
        result,
        isA<ConfigDecryptOk>(),
        reason: 'the Dart envelope no longer matches the wire format that Kotlin and Swift also implement',
      );
      expect((result as ConfigDecryptOk).json, _vectorPlaintext);
    });

    test('the vector is shaped as version(1) || nonce(12) || ct || tag(16)', () {
      final blob = _hex(_vectorBlobHex);
      expect(blob[0], ProfileConfigCipher.configVersionV1);
      expect(blob.length, 1 + 12 + _vectorPlaintext.length + 16);
    });

    test('the same blob under a different profile id fails the tag check', () async {
      final cipher = _cipherWith(_hex(_vectorKeyHex));
      final result = await cipher.decrypt(
        profileId: 'not-the-right-profile',
        blob: _hex(_vectorBlobHex),
      );
      expect(result, isA<ConfigDecryptFailed>());
      expect((result as ConfigDecryptFailed).reason, ConfigCipherRejection.authFailed);
    });
  });

  group('round trip', () {
    test('recovers a config unchanged', () async {
      final cipher = _cipherWith(key);
      const json = '{"outbounds":[{"tag":"proxy","server":"198.51.100.7"}]}';
      final blob = await cipher.encrypt(profileId: profileId, json: json);
      final result = await cipher.decrypt(profileId: profileId, blob: blob);
      expect((result as ConfigDecryptOk).json, json);
    });

    test('handles a realistically large config', () async {
      final cipher = _cipherWith(key);
      // ~1 MB — comfortably above a 200-outbound subscription.
      final json = '{"outbounds":[${List.filled(12000, '{"tag":"n","server":"203.0.113.9"}').join(',')}]}';
      final blob = await cipher.encrypt(profileId: profileId, json: json);
      final result = await cipher.decrypt(profileId: profileId, blob: blob);
      expect((result as ConfigDecryptOk).json, json);
    });

    test('handles multi-byte characters in tags', () async {
      final cipher = _cipherWith(key);
      const json = '{"outbounds":[{"tag":"东京 · 节点 🚀"}]}';
      final blob = await cipher.encrypt(profileId: profileId, json: json);
      expect((await cipher.decrypt(profileId: profileId, blob: blob) as ConfigDecryptOk).json, json);
    });

    test('the same config seals to a different blob every time', () async {
      final cipher = _cipherWith(key);
      const json = '{"outbounds":[]}';
      final a = await cipher.encrypt(profileId: profileId, json: json);
      final b = await cipher.encrypt(profileId: profileId, json: json);
      expect(a, isNot(equals(b)), reason: 'the nonce must be random per write');
      // …but both still open, i.e. the difference is the nonce and nothing else.
      expect((await cipher.decrypt(profileId: profileId, blob: b) as ConfigDecryptOk).json, json);
    });

    test('emits the declared envelope shape', () async {
      final cipher = _cipherWith(key);
      const json = '{"a":1}';
      final blob = await cipher.encrypt(profileId: profileId, json: json);
      expect(blob[0], ProfileConfigCipher.configVersionV1);
      expect(blob.length, 1 + 12 + utf8.encode(json).length + 16);
    });
  });

  group('rejects', () {
    late ProfileConfigCipher cipher;
    late Uint8List good;

    setUp(() async {
      cipher = _cipherWith(key);
      good = await cipher.encrypt(profileId: profileId, json: '{"outbounds":[]}');
    });

    Future<ConfigCipherRejection> reasonFor(Uint8List blob, {String? id}) async {
      final r = await cipher.decrypt(profileId: id ?? profileId, blob: blob);
      expect(r, isA<ConfigDecryptFailed>());
      return (r as ConfigDecryptFailed).reason;
    }

    test('a flipped bit in the tag', () async {
      final tampered = Uint8List.fromList(good)..[good.length - 1] ^= 0x01;
      expect(await reasonFor(tampered), ConfigCipherRejection.authFailed);
    });

    test('a flipped bit in the ciphertext', () async {
      final tampered = Uint8List.fromList(good)..[20] ^= 0x80;
      expect(await reasonFor(tampered), ConfigCipherRejection.authFailed);
    });

    test('a flipped bit in the nonce', () async {
      final tampered = Uint8List.fromList(good)..[1] ^= 0x40;
      expect(await reasonFor(tampered), ConfigCipherRejection.authFailed);
    });

    test('a blob belonging to another profile', () async {
      expect(await reasonFor(good, id: 'some-other-profile-id'), ConfigCipherRejection.authFailed);
    });

    test('an unknown version byte — a downgraded install, not corruption', () async {
      final future = Uint8List.fromList(good)..[0] = 0x02;
      expect(await reasonFor(future), ConfigCipherRejection.unsupportedVersion);
    });

    test('a truncated blob', () async {
      expect(await reasonFor(good.sublist(0, 28)), ConfigCipherRejection.tooShort);
    });

    test('exactly the minimum length with a valid version byte — no crash', () async {
      final minimal = Uint8List(29)..[0] = ProfileConfigCipher.configVersionV1;
      expect(await reasonFor(minimal), ConfigCipherRejection.authFailed);
    });

    test('an empty blob', () async {
      expect(await reasonFor(Uint8List(0)), ConfigCipherRejection.tooShort);
    });

    test('plaintext that is not UTF-8', () async {
      // Unreachable through encrypt(), which only ever seals a Dart String — so
      // the blob is sealed here directly. Worth covering because a future
      // writer (or a corrupted-but-authentic file) could produce it, and the
      // reader must classify it rather than throw.
      final blob = _sealRaw(key, profileId, Uint8List.fromList([0xFF, 0xFE, 0x00, 0xC0]));
      expect(await reasonFor(blob), ConfigCipherRejection.notUtf8);
    });
  });

  group('key seam', () {
    test('decrypt reports keyUnavailable rather than throwing', () async {
      final result = await _cipherWith(null).decrypt(profileId: profileId, blob: Uint8List(64));
      expect((result as ConfigDecryptFailed).reason, ConfigCipherRejection.keyUnavailable);
    });

    test('encrypt refuses to write anything without a key', () {
      expect(
        () => _cipherWith(null).encrypt(profileId: profileId, json: '{}'),
        throwsA(
          isA<ConfigCipherException>().having((e) => e.reason, 'reason', ConfigCipherRejection.keyUnavailable),
        ),
      );
    });

    test('a config sealed under one key does not open under another', () async {
      final blob = await _cipherWith(key).encrypt(profileId: profileId, json: '{"outbounds":[]}');
      final other = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
      final result = await _cipherWith(other).decrypt(profileId: profileId, blob: blob);
      expect((result as ConfigDecryptFailed).reason, ConfigCipherRejection.authFailed);
    });

    test('the injected key survives repeated use', () async {
      final cipher = _cipherWith(key);
      for (var i = 0; i < 3; i++) {
        final blob = await cipher.encrypt(profileId: profileId, json: '{"i":$i}');
        expect((await cipher.decrypt(profileId: profileId, blob: blob) as ConfigDecryptOk).json, '{"i":$i}');
      }
    });
  });
}
