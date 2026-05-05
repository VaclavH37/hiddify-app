// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/link_parsers.dart';
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

void main() {
  setUpAll(() {
    _testKey = CryptoUtils.generateRSAKeyPair(keySize: 4096);
  });

  setUp(() {
    RaynTokenDecryptor.debugSetKey(_testKey.privateKey as RSAPrivateKey);
  });

  group('rayn:// link parsing', () {
    test('end-to-end: rayn://import/<token> decrypts to subscription URL', () {
      const url = 'https://subscription-api.example.com/MyMixedCasePath?x=1';
      final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
      final link = 'rayn://import/$token';

      final result = LinkParser.parse(link);
      expect(result, isNotNull);
      expect(result!.url, url);
    });

    test('mixed-case base64url survives URI parsing (regression: host lowercases)', () {
      // This is the core regression: any token containing uppercase chars must
      // round-trip without being lowercased by Dart's Uri parser.
      const url = 'https://example.com/test';
      final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
      // Sanity: tokens routinely contain uppercase letters
      expect(token.toLowerCase() != token, isTrue, reason: 'expected mixed case in base64url');

      final result = LinkParser.parse('rayn://import/$token');
      expect(result?.url, url);
    });

    test('rejects rayn:// without /import/ prefix (legacy authority-only format)', () {
      const url = 'https://example.com/test';
      final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
      // Old format: token in authority — must NOT decrypt successfully.
      final result = LinkParser.parse('rayn://$token');
      expect(result, isNull);
    });

    test('rejects rayn://import/ with empty token', () {
      expect(LinkParser.parse('rayn://import/'), isNull);
      expect(LinkParser.parse('rayn://import'), isNull);
    });

    test('rejects rayn://other-host/<token>', () {
      const url = 'https://example.com/test';
      final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
      expect(LinkParser.parse('rayn://something-else/$token'), isNull);
    });
  });

  group('legacy schemes are rejected', () {
    for (final scheme in const [
      'hiddify',
      'v2ray',
      'v2rayn',
      'v2rayng',
      'clash',
      'clashmeta',
      'sing-box',
    ]) {
      test('$scheme:// is no longer accepted', () {
        // Both the import-style path and the ?url= query-param form must
        // return null now that only `rayn` is in `LinkParser.protocols`.
        expect(LinkParser.parse('$scheme://import/https://example.com/sub'), isNull);
        expect(LinkParser.parse('$scheme://x?url=https%3A%2F%2Fexample.com'), isNull);
      });
    }

    test('bare https URL is rejected (no more simple() fallback)', () {
      expect(LinkParser.parse('https://example.com/sub'), isNull);
      expect(LinkParser.parse('https://subscription-api.example.com/abc?name=foo'), isNull);
    });

    test('protocols list contains only rayn', () {
      expect(LinkParser.protocols, ['rayn']);
    });
  });
}
