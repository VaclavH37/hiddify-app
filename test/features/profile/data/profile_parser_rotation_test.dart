import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';

import '../../../support/rayn_link_fixture.dart';

void main() {
  setUp(useTestSecret);
  tearDown(useEmbeddedKey);

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
      final link = mintRaynLink(url);

      final result = ProfileParser.extractRotation({'new-url': link});

      expect(result, isNotNull);
      expect(result!.url, url);
      // sourceToken carries the raw rayn:// link for persistence.
      expect(result.sourceToken, link);
    });

    test('trims surrounding whitespace before parsing', () {
      const url = 'https://api.example.com/sub';
      final link = mintRaynLink(url);

      final result = ProfileParser.extractRotation({'new-url': '  $link  '});

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.sourceToken, link);
    });

    test('takes first element when header is a multi-value list', () {
      const url = 'https://api.example.com/sub';
      final link = mintRaynLink(url);

      final result = ProfileParser.extractRotation({
        'new-url': [link, 'rayn://import/ignored_second_value'],
      });

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.sourceToken, link);
    });

    test('returns null when multi-value list is empty', () {
      expect(ProfileParser.extractRotation({'new-url': const <String>[]}), isNull);
    });

    test('returns null when value is an unsupported type', () {
      expect(ProfileParser.extractRotation(const {'new-url': 42}), isNull);
      expect(ProfileParser.extractRotation(const {'new-url': null}), isNull);
    });

    test('rejects rotation when the underlying decrypt fails (different secret)', () {
      final link = mintRaynLink('https://api.example.com/sub', secret: 'a-different-secret');
      expect(ProfileParser.extractRotation({'new-url': link}), isNull);
    });

    test('rejects an envelope version this build cannot open', () {
      // Must not be followed, and must not throw — the caller keeps using the
      // current URL and the error log tells us an app update is due.
      final link = mintRaynLink('https://api.example.com/sub', version: 0x03);
      expect(ProfileParser.extractRotation({'new-url': link}), isNull);
    });

    test('two links for the same URL differ but decrypt identically', () {
      // The precondition behind the §4 rule: rotation must be detected by
      // comparing decrypted URLs, because the cryptolink strings never match.
      const url = 'https://api.example.com/sub';
      final first = mintRaynLink(url);
      final second = mintRaynLink(url);

      expect(first, isNot(second), reason: 'GCM nonce is random — links are not comparable (§4)');
      expect(ProfileParser.extractRotation({'new-url': first})!.url, url);
      expect(ProfileParser.extractRotation({'new-url': second})!.url, url);
    });
  });
}
