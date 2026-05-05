// pointycastle is a transitive dep of basic_utils; we import OAEPEncoding +
// RSAEngine directly because basic_utils only re-exports the asymmetric
// `api.dart` (key types) and not the cipher engines we need for OAEP-SHA-256.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:loggy/loggy.dart';
import 'package:meta/meta.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

/// Decrypts `rayn://<base64url(rsa_ciphertext)>` deep-link tokens.
///
/// Backend RSA-4096 / OAEP-SHA-256 encrypts a subscription URL with the
/// public key; the matching private key ships as a bundled asset and is
/// used here to recover the URL. See `project_rayn_crypto_scheme` memory
/// for why the key direction is what it is (obfuscation, not auth).
abstract class RaynTokenDecryptor {
  static const _assetPath = 'assets/keys/rayn_private_key.pem';
  static const _expectedCiphertextBytes = 512; // RSA-4096 block size
  static final _log = Loggy('rayn_token');

  static RSAPrivateKey? _privateKey;
  static bool get isLoaded => _privateKey != null;

  /// Loads and parses the bundled PEM. Idempotent. Failures are logged but
  /// not thrown — `decryptToUrl` will then reject every token, surfacing as
  /// "invalid link" rather than crashing the app.
  static Future<void> load() async {
    if (_privateKey != null) return;
    try {
      final pem = await rootBundle.loadString(_assetPath);
      _privateKey = CryptoUtils.rsaPrivateKeyFromPem(pem);
    } catch (e, st) {
      _log.error('failed to load rayn private key from $_assetPath', e, st);
    }
  }

  /// Pre-parsed key injection for tests.
  @visibleForTesting
  static void debugSetKey(RSAPrivateKey? key) => _privateKey = key;

  /// Verifies and decrypts [tokenSegment] (the part after `rayn://`).
  /// Returns the recovered subscription URL, or null on any failure.
  static String? decryptToUrl(String tokenSegment) {
    final key = _privateKey;
    if (key == null) {
      _log.warning('decryptToUrl called before load() completed');
      return null;
    }
    if (tokenSegment.isEmpty) return null;

    final Uint8List ciphertext;
    try {
      ciphertext = base64Url.decode(_padBase64Url(tokenSegment));
    } catch (_) {
      return null;
    }
    if (ciphertext.length != _expectedCiphertextBytes) {
      _log.warning(
        'rayn token ciphertext is ${ciphertext.length} bytes, expected $_expectedCiphertextBytes',
      );
      return null;
    }

    final Uint8List plaintext;
    try {
      final cipher = OAEPEncoding.withSHA256(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(key));
      plaintext = cipher.process(ciphertext);
    } catch (e) {
      _log.warning('rayn token OAEP decryption failed: $e');
      return null;
    }

    final String url;
    try {
      url = utf8.decode(plaintext);
    } catch (_) {
      _log.warning('rayn token plaintext is not valid UTF-8');
      return null;
    }
    if (!url.startsWith('https://')) {
      _log.warning('rayn token plaintext is not an https URL');
      return null;
    }
    return url;
  }

  static String _padBase64Url(String input) {
    final mod = input.length % 4;
    return mod == 0 ? input : input + ('=' * (4 - mod));
  }
}
