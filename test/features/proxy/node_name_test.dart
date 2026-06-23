import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';

void main() {
  group('prettifyNodeName', () {
    test('transforms a hub tag to "City, CC"', () {
      expect(prettifyNodeName('HUB-JP-TOKYO-A'), 'Tokyo, JP');
    });

    test('transforms an exit tag (with trailing flag) to "City, CC"', () {
      expect(prettifyNodeName('EXIT-US-DALLAS-01🇺🇸'), 'Dallas, US');
    });

    test('handles multi-word (hyphenated) cities', () {
      expect(prettifyNodeName('EXIT-US-NEW-YORK-02'), 'New York, US');
    });

    test('uses only the primary hop for a chained (detour) tag', () {
      // The core renders an exit routed through a hub as "<exit> → <hub>".
      expect(prettifyNodeName('EXIT-US-DALLAS-01🇺🇸 → HUB-JP-TOKYO-A'), 'Dallas, US');
      // Tolerate the ASCII arrow form too.
      expect(prettifyNodeName('EXIT-US-DALLAS-01->HUB-JP-TOKYO-A'), 'Dallas, US');
    });

    test('title-cases the city and upper-cases the country code', () {
      expect(prettifyNodeName('hub-jp-tokyo-a'), 'Tokyo, JP');
    });

    test('returns null for tags that do not match the convention', () {
      expect(prettifyNodeName('→ Remnawave'), isNull);
      expect(prettifyNodeName('round-robin'), isNull); // wrong prefix
      expect(prettifyNodeName('Tokyo, JP'), isNull); // already readable
      expect(prettifyNodeName('HUB-JPN-TOKYO-A'), isNull); // 3-letter country code
      expect(prettifyNodeName('HUB-JP-A'), isNull); // missing city segment
    });
  });

  group('stripTrailingFlag', () {
    test('removes a trailing country flag and surrounding whitespace', () {
      expect(stripTrailingFlag('Dallas 🇺🇸'), 'Dallas');
    });

    test('leaves names without a trailing flag unchanged', () {
      expect(stripTrailingFlag('Tokyo, JP'), 'Tokyo, JP');
    });
  });
}
