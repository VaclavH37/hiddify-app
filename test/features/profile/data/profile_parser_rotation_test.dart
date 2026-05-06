// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/utils/rayn_token.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

late AsymmetricKeyPair _testKey;

String _encrypt(String url, RSAPublicKey publicKey) {
  final cipher = OAEPEncoding.withSHA256(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  final ciphertext = cipher.process(Uint8List.fromList(utf8.encode(url)));
  return base64Url.encode(ciphertext).replaceAll('=', '');
}

String _raynLink(String url) {
  final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
  return 'rayn://import/$token';
}

void main() {
  setUpAll(() {
    _testKey = CryptoUtils.generateRSAKeyPair(keySize: 4096);
  });

  setUp(() {
    RaynTokenDecryptor.debugSetKey(_testKey.privateKey as RSAPrivateKey);
  });

  group('extractRotation', () {
    test('returns null when `new-url` header is absent', () {
      expect(ProfileParser.extractRotation(const {}), isNull);
      expect(
        ProfileParser.extractRotation(const {'content-type': 'application/json'}),
        isNull,
      );
    });

    test('returns null on empty / whitespace header', () {
      expect(ProfileParser.extractRotation(const {'new-url': ''}), isNull);
      expect(ProfileParser.extractRotation(const {'new-url': '   '}), isNull);
    });

    test('returns null when value is non-rayn https URL', () {
      expect(
        ProfileParser.extractRotation(const {'new-url': 'https://malicious.example.com/sub'}),
        isNull,
      );
    });

    test('returns null on rayn:// without /import/ prefix', () {
      expect(
        ProfileParser.extractRotation(const {'new-url': 'rayn://something/abc'}),
        isNull,
      );
    });

    test('returns null on rayn://import/ with empty token', () {
      expect(ProfileParser.extractRotation(const {'new-url': 'rayn://import/'}), isNull);
    });

    test('returns null when the rayn://import/<token> ciphertext is garbage', () {
      expect(
        ProfileParser.extractRotation(const {'new-url': 'rayn://import/not_a_real_token_x'}),
        isNull,
      );
    });

    test('returns decrypted url and full rayn:// link when header is valid', () {
      const url = 'https://api.example.com/sub/abc?x=1';
      final link = _raynLink(url);

      final result = ProfileParser.extractRotation({'new-url': link});

      expect(result, isNotNull);
      expect(result!.url, url);
      // `name` channel reused to carry the raw rayn:// link for sourceToken.
      expect(result.name, link);
    });

    test('trims surrounding whitespace before parsing', () {
      const url = 'https://api.example.com/sub';
      final link = _raynLink(url);

      final result = ProfileParser.extractRotation({'new-url': '  $link  '});

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.name, link);
    });

    test('takes first element when header is a multi-value list', () {
      const url = 'https://api.example.com/sub';
      final link = _raynLink(url);

      final result = ProfileParser.extractRotation({
        'new-url': [link, 'rayn://import/ignored_second_value'],
      });

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.name, link);
    });

    test('returns null when multi-value list is empty', () {
      expect(ProfileParser.extractRotation({'new-url': const <String>[]}), isNull);
    });

    test('returns null when value is an unsupported type', () {
      expect(ProfileParser.extractRotation(const {'new-url': 42}), isNull);
      expect(ProfileParser.extractRotation(const {'new-url': null}), isNull);
    });

    test('rejects rotation when the underlying decrypt fails (different key)', () {
      final otherKey = CryptoUtils.generateRSAKeyPair(keySize: 4096);
      final token = _encrypt('https://api.example.com/sub', otherKey.publicKey as RSAPublicKey);
      expect(
        ProfileParser.extractRotation({'new-url': 'rayn://import/$token'}),
        isNull,
      );
    });
  });
}
