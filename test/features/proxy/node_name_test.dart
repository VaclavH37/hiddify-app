import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';

void main() {
  group('displayNodeTag', () {
    test('strips the EXIT- prefix and a trailing flag', () {
      expect(displayNodeTag('EXIT-Tokyo, JP🇯🇵'), 'Tokyo, JP');
      expect(displayNodeTag('EXIT-Los Angeles, US🇺🇸'), 'Los Angeles, US');
    });

    test('strips the EXIT- prefix even without a flag', () {
      expect(displayNodeTag('EXIT-Tokyo, JP'), 'Tokyo, JP');
    });

    test('leaves a tag without the EXIT- prefix untouched (aside from flag)', () {
      expect(displayNodeTag('Tokyo, JP🇯🇵'), 'Tokyo, JP');
      expect(displayNodeTag('lowest'), 'lowest');
    });

    test('only strips a leading EXIT-, not one mid-string', () {
      expect(displayNodeTag('My-EXIT-node'), 'My-EXIT-node');
    });

    test('is case-sensitive on the prefix (matches the uppercase convention)', () {
      expect(displayNodeTag('exit-Tokyo'), 'exit-Tokyo');
    });
  });

  group('stripTrailingFlag', () {
    test('removes a trailing country-flag emoji and surrounding whitespace', () {
      expect(stripTrailingFlag('Dallas 🇺🇸'), 'Dallas');
    });

    test('removes multiple trailing flags', () {
      expect(stripTrailingFlag('Somewhere 🇺🇸🇯🇵'), 'Somewhere');
    });

    test('leaves text without a trailing flag untouched', () {
      expect(stripTrailingFlag('Tokyo, JP'), 'Tokyo, JP');
    });

    test('does not strip a flag that is not trailing', () {
      expect(stripTrailingFlag('🇺🇸 Dallas'), '🇺🇸 Dallas');
    });
  });
}
