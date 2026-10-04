import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:pointycastle/export.dart';

// Signing side of the Windows updater: key generation, the encrypted key file
// and envelope signing. Used by `tool/publish_windows_update.dart` and the
// tests. Nothing in the app imports this file, so it never ships in a build;
// the app only verifies (update_manifest.dart).

/// Generates a P-256 key pair from a cryptographically secure seed.
AsymmetricKeyPair<ECPublicKey, ECPrivateKey> generateUpdateKeyPair([Random? seedSource]) {
  final seeds = seedSource ?? Random.secure();
  final random = FortunaRandom()
    ..seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (_) => seeds.nextInt(256)))));
  final generator = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(updateCurve), random));
  final pair = generator.generateKeyPair();
  return AsymmetricKeyPair(pair.publicKey as ECPublicKey, pair.privateKey as ECPrivateKey);
}

/// Signs [payload] (the exact bytes clients will verify) and returns the
/// envelope JSON. Deterministic ECDSA (RFC 6979): no random nonce to get wrong.
String signUpdateEnvelope({required List<int> payload, required String keyId, required ECPrivateKey key}) {
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(key));
  final signature = signer.generateSignature(Uint8List.fromList(payload)) as ECSignature;
  final bytes = Uint8List(64)
    ..setRange(0, 32, _fixed32(signature.r))
    ..setRange(32, 64, _fixed32(signature.s));
  return jsonEncode({'key_id': keyId, 'payload': base64.encode(payload), 'signature': base64.encode(bytes)});
}

/// The payload bytes for [manifest]: what is signed and what clients parse.
List<int> encodeUpdatePayload(UpdateManifest manifest) => utf8.encode(jsonEncode(manifest.toJson()));

// --- the private key at rest ------------------------------------------------

const _keyFileFormat = 'rayn-update-key-v1';

/// PBKDF2-HMAC-SHA256 rounds for the key file's passphrase (OWASP's 2023
/// figure). Tests pass fewer.
const kUpdateKeyFileIterations = 600000;

class UpdateKeyFileException implements Exception {
  const UpdateKeyFileException(this.reason);

  final String reason;

  @override
  String toString() => 'update key file: $reason';
}

/// The private key, encrypted with a passphrase: PBKDF2-HMAC-SHA256, then
/// AES-256-GCM over the 32-byte scalar, with the key id and public key as
/// associated data so neither can be swapped in the file. Returns the file's
/// JSON.
String encryptUpdateKeyFile({
  required ECPrivateKey key,
  required ECPublicKey publicKey,
  required String keyId,
  required String passphrase,
  int iterations = kUpdateKeyFileIterations,
  Random? random,
}) {
  final source = random ?? Random.secure();
  final salt = Uint8List.fromList(List<int>.generate(16, (_) => source.nextInt(256)));
  final nonce = Uint8List.fromList(List<int>.generate(12, (_) => source.nextInt(256)));
  final publicB64 = encodeUpdatePublicKey(publicKey);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(_derive(passphrase, salt, iterations)), 128, nonce, _aad(keyId, publicB64)),
    );
  final ciphertext = cipher.process(_fixed32(key.d!));
  return const JsonEncoder.withIndent('  ').convert({
    'format': _keyFileFormat,
    'key_id': keyId,
    'public_key': publicB64,
    'kdf': 'pbkdf2-sha256',
    'iterations': iterations,
    'salt': base64.encode(salt),
    'nonce': base64.encode(nonce),
    'ciphertext': base64.encode(ciphertext),
  });
}

/// Opens a key file written by [encryptUpdateKeyFile]. A wrong passphrase, or
/// any edit to the file, fails the AES-GCM tag.
({String keyId, ECPrivateKey key, ECPublicKey publicKey}) decryptUpdateKeyFile(String json, String passphrase) {
  final Map<String, dynamic> file;
  try {
    file = jsonDecode(json) as Map<String, dynamic>;
  } catch (_) {
    throw const UpdateKeyFileException('not a key file');
  }
  if (file['format'] != _keyFileFormat || file['kdf'] != 'pbkdf2-sha256') {
    throw const UpdateKeyFileException('unknown key file format');
  }
  final keyId = file['key_id'] as String;
  final publicB64 = file['public_key'] as String;
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(_derive(passphrase, base64.decode(file['salt'] as String), file['iterations'] as int)),
        128,
        base64.decode(file['nonce'] as String),
        _aad(keyId, publicB64),
      ),
    );
  final Uint8List scalar;
  try {
    scalar = cipher.process(base64.decode(file['ciphertext'] as String));
  } on InvalidCipherTextException {
    throw const UpdateKeyFileException('wrong passphrase, or the file was altered');
  }
  final publicKey = decodeUpdatePublicKey(publicB64);
  final key = ECPrivateKey(_bigInt(scalar), updateCurve);
  // The scalar must produce the public key the file names.
  if ((updateCurve.G * key.d)! != publicKey.Q) {
    throw const UpdateKeyFileException('private key does not match its public key');
  }
  return (keyId: keyId, key: key, publicKey: publicKey);
}

Uint8List _derive(String passphrase, Uint8List salt, int iterations) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(salt, iterations, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(passphrase)));
}

Uint8List _aad(String keyId, String publicB64) => Uint8List.fromList(utf8.encode('$_keyFileFormat|$keyId|$publicB64'));

Uint8List _fixed32(BigInt value) {
  final out = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  if (v != BigInt.zero) throw ArgumentError('value does not fit in 32 bytes');
  return out;
}

BigInt _bigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}
