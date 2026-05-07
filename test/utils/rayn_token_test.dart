// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/rayn_token.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

late AsymmetricKeyPair _testKey;
late AsymmetricKeyPair _otherKey;

String _encrypt(String url, RSAPublicKey publicKey) {
  final cipher = OAEPEncoding.withSHA256(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  final ciphertext = cipher.process(Uint8List.fromList(utf8.encode(url)));
  return base64Url.encode(ciphertext).replaceAll('=', '');
}

void main() {
  setUpAll(() {
    _testKey = CryptoUtils.generateRSAKeyPair(keySize: 4096);
    _otherKey = CryptoUtils.generateRSAKeyPair(keySize: 4096);
  });

  setUp(() {
    RaynTokenDecryptor.debugSetKey(_testKey.privateKey as RSAPrivateKey);
  });

  test('decrypts a token encrypted with the matching public key', () {
    const url = 'https://subscription-api.example.com/abc123';
    final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
    expect(RaynTokenDecryptor.decryptToUrl(token), url);
  });

  test('rejects a token encrypted with a different public key', () {
    final token = _encrypt('https://x.example.com', _otherKey.publicKey as RSAPublicKey);
    expect(RaynTokenDecryptor.decryptToUrl(token), null);
  });

  test('rejects ciphertext shorter than 512 bytes', () {
    final shortToken = base64Url.encode(Uint8List(64)).replaceAll('=', '');
    expect(RaynTokenDecryptor.decryptToUrl(shortToken), null);
  });

  test('rejects ciphertext with the wrong length even if base64 is valid', () {
    final wrongSize = base64Url.encode(Uint8List(256)).replaceAll('=', '');
    expect(RaynTokenDecryptor.decryptToUrl(wrongSize), null);
  });

  test('rejects garbage non-base64 input', () {
    expect(RaynTokenDecryptor.decryptToUrl('not!valid#base64@@@'), null);
  });

  test('rejects empty input', () {
    expect(RaynTokenDecryptor.decryptToUrl(''), null);
  });

  test('rejects plaintext that is not an https URL', () {
    final token = _encrypt('javascript:alert(1)', _testKey.publicKey as RSAPublicKey);
    expect(RaynTokenDecryptor.decryptToUrl(token), null);
  });

  test('accepts plain http in debug mode (dev bypass for local test server)', () {
    // Tests always run in debug mode (kDebugMode == true). This is a flipped
    // version of the prior "rejects plaintext that is plain http" assertion;
    // release builds still reject http:// — see rayn_token.dart for the gate.
    const url = 'http://localhost:8080/sub';
    final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
    expect(RaynTokenDecryptor.decryptToUrl(token), url);
  });

  test('returns null when key has not been loaded', () {
    RaynTokenDecryptor.debugSetKey(null);
    final token = _encrypt('https://x.example.com', _testKey.publicKey as RSAPublicKey);
    expect(RaynTokenDecryptor.decryptToUrl(token), null);
  });

  test('produces a token of expected base64url length (~683 chars)', () {
    final token = _encrypt('https://x.example.com', _testKey.publicKey as RSAPublicKey);
    // RSA-4096 ciphertext = 512 bytes; base64 of 512 bytes = ceil(512/3)*4 = 684, minus padding
    expect(token.length, inInclusiveRange(680, 684));
  });
}
