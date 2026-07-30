import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/link_parsers.dart';
import 'package:hiddify/utils/rayn_token.dart';

import '../support/rayn_link_fixture.dart';

void main() {
  setUp(useTestSecret);
  tearDown(useEmbeddedKey);

  group('rayn:// link parsing', () {
    test('end-to-end: rayn://import/<token> decrypts to subscription URL', () {
      const url = 'https://subscription-api.example.com/MyMixedCasePath?x=1';
      final result = LinkParser.parse(mintRaynLink(url));
      expect(result, isA<RaynLinkOk>());
      expect((result as RaynLinkOk).url, url);
    });

    test('mixed-case base64url survives URI parsing (regression: host lowercases)', () {
      // The core regression: any token containing uppercase chars must round-trip
      // without being lowercased by Dart's Uri parser. The nonce is pinned so the
      // assertion below can't be flaky.
      const url = 'https://example.com/test';
      final nonce = Uint8List.fromList(List<int>.generate(12, (i) => 0xA0 + i));
      final link = mintRaynLink(url, nonce: nonce);
      final token = link.substring(kRaynLinkPrefix.length);
      expect(token.toLowerCase() != token, isTrue, reason: 'expected mixed case in base64url');

      expect((LinkParser.parse(link) as RaynLinkOk).url, url);
    });

    test('trims surrounding whitespace', () {
      const url = 'https://example.com/test';
      expect((LinkParser.parse('  ${mintRaynLink(url)}\n') as RaynLinkOk).url, url);
    });

    test('rejects rayn:// without /import/ prefix (legacy authority-only format)', () {
      final token = mintRaynToken('https://example.com/test');
      // Old format: token in authority — must NOT decrypt successfully.
      expect(LinkParser.parse('rayn://$token'), isA<RaynLinkInvalid>());
    });

    test('rejects rayn://import/ with empty token', () {
      expect((LinkParser.parse('rayn://import/') as RaynLinkInvalid).reason, RaynLinkRejection.empty);
      // `rayn://import` has no path at all — indistinguishable from a bad link.
      expect(LinkParser.parse('rayn://import'), isA<RaynLinkInvalid>());
    });

    test('rejects rayn://other-host/<token>', () {
      final token = mintRaynToken('https://example.com/test');
      expect(
        (LinkParser.parse('rayn://something-else/$token') as RaynLinkInvalid).reason,
        RaynLinkRejection.notARaynLink,
      );
    });

    test('surfaces an unsupported envelope version through the parser', () {
      // Must reach the caller as "update the app", not "invalid link" (§10).
      final link = mintRaynLink('https://example.com/test', version: 0x03);
      final result = LinkParser.parse(link);
      expect(result, isA<RaynLinkUnsupportedVersion>());
      expect((result as RaynLinkUnsupportedVersion).version, 0x03);
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
        // Both the import-style path and the ?url= query-param form must be
        // rejected now that only `rayn` is in `LinkParser.protocols`.
        expect(LinkParser.parse('$scheme://import/https://example.com/sub'), isA<RaynLinkInvalid>());
        expect(LinkParser.parse('$scheme://x?url=https%3A%2F%2Fexample.com'), isA<RaynLinkInvalid>());
      });
    }

    test('bare https URL is rejected (no more simple() fallback)', () {
      expect(LinkParser.parse('https://example.com/sub'), isA<RaynLinkInvalid>());
      expect(LinkParser.parse('https://subscription-api.example.com/abc?name=foo'), isA<RaynLinkInvalid>());
    });

    test('protocols list contains only rayn', () {
      expect(LinkParser.protocols, ['rayn']);
    });
  });
}
