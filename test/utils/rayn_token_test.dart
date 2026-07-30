import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/rayn_token.dart';

import '../support/rayn_link_fixture.dart';

/// Strips `rayn://import/` so a full vector can be fed to
/// [RaynTokenDecryptor.decrypt], which takes only the payload.
String _token(String link) => link.substring(kRaynLinkPrefix.length);

void main() {
  setUp(useTestSecret);
  tearDown(useEmbeddedKey);

  // Runs first on purpose: if key derivation is wrong, every other group fails
  // with an authentication error that looks like a wrong secret.
  group('key derivation (§6.3)', () {
    test('hashes the secret STRING, not its hex-decoded bytes', () {
      expect(
        hex(RaynTokenDecryptor.deriveKey(kHexLookingSecret)),
        kHexLookingSecretKeyHex,
        reason: 'the secret is 64 ASCII characters — hash those, do not hex-decode first (§6.3)',
      );
      expect(
        hex(RaynTokenDecryptor.deriveKey(kHexLookingSecret)),
        isNot(kHexDecodedWrongKeyHex),
        reason: 'this is the value you get if you wrongly hex-decode the secret to 32 bytes (§6.3)',
      );
    });

    test('derives the published conformance key', () {
      expect(hex(RaynTokenDecryptor.deriveKey(kConformanceSecret)), kConformanceKeyHex);
    });

    test('always produces a 32-byte key', () {
      expect(RaynTokenDecryptor.deriveKey('').length, 32);
      expect(RaynTokenDecryptor.deriveKey('a' * 4096).length, 32);
    });
  });

  group('conformance vectors (§8)', () {
    test('V1 decrypts to the published plaintext', () {
      final result = RaynTokenDecryptor.decrypt(_token(kVectorV1));
      expect(result, isA<RaynLinkOk>());
      expect((result as RaynLinkOk).url, kVectorV1Plain);
      expect(result.url.length, 63);
    });

    test('V2 decrypts a 563-byte plaintext (117 bytes over the old RSA ceiling)', () {
      final result = RaynTokenDecryptor.decrypt(_token(kVectorV2));
      expect(result, isA<RaynLinkOk>());
      expect((result as RaynLinkOk).url, kVectorV2Plain);
      expect(result.url.length, 563);
    });

    test('V3 is an UNSUPPORTED VERSION, not an authentication failure', () {
      final result = RaynTokenDecryptor.decrypt(_token(kVectorV3));
      expect(result, isA<RaynLinkUnsupportedVersion>());
      expect((result as RaynLinkUnsupportedVersion).version, 0x01);
      // The point of this vector: the version check must run BEFORE the AEAD
      // open, so the user gets "please update", not "invalid link".
      expect(result, isNot(isA<RaynLinkInvalid>()));
    });

    test('V4 fails authentication and yields no plaintext', () {
      final result = RaynTokenDecryptor.decrypt(_token(kVectorV4));
      expect(result, isA<RaynLinkInvalid>());
      expect((result as RaynLinkInvalid).reason, RaynLinkRejection.authFailed);
      expect(result, isNot(isA<RaynLinkOk>()));
    });
  });

  group('malformed input (§8 "also assert")', () {
    test('rejects an empty or whitespace-only payload', () {
      expect((RaynTokenDecryptor.decrypt('') as RaynLinkInvalid).reason, RaynLinkRejection.empty);
      expect((RaynTokenDecryptor.decrypt('   ') as RaynLinkInvalid).reason, RaynLinkRejection.empty);
    });

    test('rejects a non-base64 payload', () {
      expect(
        (RaynTokenDecryptor.decrypt('not!valid#base64@@@') as RaynLinkInvalid).reason,
        RaynLinkRejection.badBase64,
      );
    });

    test('rejects a blob shorter than 29 bytes', () {
      final short = base64Url.encode(Uint8List(28)).replaceAll('=', '');
      expect((RaynTokenDecryptor.decrypt(short) as RaynLinkInvalid).reason, RaynLinkRejection.tooShort);
    });

    test('handles a minimal 29-byte v2 blob without crashing', () {
      final blob = Uint8List(29)..[0] = kLinkVersionV2;
      final token = base64Url.encode(blob).replaceAll('=', '');
      expect((RaynTokenDecryptor.decrypt(token) as RaynLinkInvalid).reason, RaynLinkRejection.authFailed);
    });

    test('a truncated valid link fails authentication, never returns plaintext', () {
      final blob = blobOfLink(kVectorV1);
      final truncated = base64Url.encode(blob.sublist(0, blob.length - 1)).replaceAll('=', '');
      final result = RaynTokenDecryptor.decrypt(truncated);
      expect(result, isNot(isA<RaynLinkOk>()));
      expect((result as RaynLinkInvalid).reason, RaynLinkRejection.authFailed);
    });

    test('tolerates surrounding whitespace on a valid payload', () {
      expect(RaynTokenDecryptor.decrypt('  ${_token(kVectorV1)}\n'), isA<RaynLinkOk>());
    });

    test('rejects a legacy 512-byte RSA blob cleanly, whatever byte 0 is', () {
      final legacy = Uint8List(512);
      for (var i = 0; i < 512; i++) {
        legacy[i] = (i * 7 + 13) & 0xFF;
      }

      legacy[0] = 0x00;
      final asOldVersion = RaynTokenDecryptor.decrypt(base64Url.encode(legacy).replaceAll('=', ''));
      expect(asOldVersion, isA<RaynLinkUnsupportedVersion>());

      legacy[0] = kLinkVersionV2;
      final asCurrentVersion = RaynTokenDecryptor.decrypt(base64Url.encode(legacy).replaceAll('=', ''));
      expect(asCurrentVersion, isA<RaynLinkInvalid>());
      expect((asCurrentVersion as RaynLinkInvalid).reason, RaynLinkRejection.authFailed);
    });
  });

  group('plaintext guards', () {
    test('rejects a non-https plaintext', () {
      expect(
        (RaynTokenDecryptor.decrypt(mintRaynToken('http://localhost:8080/sub')) as RaynLinkInvalid).reason,
        RaynLinkRejection.notHttps,
      );
      expect(
        (RaynTokenDecryptor.decrypt(mintRaynToken('javascript:alert(1)')) as RaynLinkInvalid).reason,
        RaynLinkRejection.notHttps,
      );
    });

    test('rejects a plaintext that is not valid UTF-8', () {
      final token = mintRaynTokenBytes(Uint8List.fromList([0xFF, 0xFE, 0xFF]));
      expect((RaynTokenDecryptor.decrypt(token) as RaynLinkInvalid).reason, RaynLinkRejection.notUtf8);
    });
  });

  group('key seam', () {
    test('reports keyUnavailable when no key is present', () {
      RaynTokenDecryptor.debugSetKey(null);
      expect(
        (RaynTokenDecryptor.decrypt(_token(kVectorV1)) as RaynLinkInvalid).reason,
        RaynLinkRejection.keyUnavailable,
      );
      expect(RaynTokenDecryptor.isLoaded, isFalse);
    });

    test('rejects a key of the wrong length', () {
      RaynTokenDecryptor.debugSetKey(Uint8List(16));
      expect(RaynTokenDecryptor.decrypt(_token(kVectorV1)), isA<RaynLinkInvalid>());
    });

    test('a different secret fails authentication', () {
      useTestSecret('some-other-secret');
      expect(
        (RaynTokenDecryptor.decrypt(_token(kVectorV1)) as RaynLinkInvalid).reason,
        RaynLinkRejection.authFailed,
      );
    });

    test('the injected key survives repeated decrypts', () {
      // Regression: decrypt() scrubs the key buffer it is handed, so _key() must
      // hand back a copy or the second call silently fails.
      expect(RaynTokenDecryptor.decrypt(_token(kVectorV1)), isA<RaynLinkOk>());
      expect(RaynTokenDecryptor.decrypt(_token(kVectorV1)), isA<RaynLinkOk>());
    });

    test('load() never throws, even with no key', () async {
      RaynTokenDecryptor.debugSetKey(null);
      await expectLater(RaynTokenDecryptor.load(), completes);
    });
  });

  group('round trip', () {
    test('handles a minimal path', () {
      final result = RaynTokenDecryptor.decrypt(mintRaynToken('https://a.io/s/x'));
      expect((result as RaynLinkOk).url, 'https://a.io/s/x');
    });

    test('handles a long URL', () {
      final url = 'https://subscription.example.com/s/${'A' * 560}';
      expect((RaynTokenDecryptor.decrypt(mintRaynToken(url)) as RaynLinkOk).url, url);
    });

    test('handles multi-byte CJK characters — the regression this migration exists for', () {
      // 12 CJK characters in a display name pushed the old RSA-OAEP plaintext
      // past its 446-byte ceiling and permanently broke those accounts (§2).
      const url = 'https://sub.example.com/s/token?name=中文名字測試用戶名稱';
      expect((RaynTokenDecryptor.decrypt(mintRaynToken(url)) as RaynLinkOk).url, url);
    });

    test('the same URL encrypts to a different link every time', () {
      // The precondition that makes §4's "cryptolinks are not comparable" rule
      // true — and therefore why rotation/fallback compare decrypted URLs.
      const url = 'https://sub.example.com/s/token';
      expect(mintRaynLink(url), isNot(mintRaynLink(url)));
    });

    test('link length tracks plaintext length — no fixed-size assumption', () {
      final short = mintRaynLink('https://a.io/s/x');
      final long = mintRaynLink('https://subscription.example.com/s/${'A' * 400}');
      expect(short.length, lessThan(long.length));
    });
  });
}
