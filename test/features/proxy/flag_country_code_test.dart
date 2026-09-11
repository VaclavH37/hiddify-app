import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// The flag comes from the tag the middleware authored, not from the
/// connection probe's guess about where the probe came out.
void main() {
  group('countryCodeFromTag', () {
    test('reads the trailing flag', () {
      expect(countryCodeFromTag('EXIT-Tokyo, JP🇯🇵'), 'JP');
      expect(countryCodeFromTag('EXIT-Los Angeles, US🇺🇸 '), 'US');
      expect(countryCodeFromTag('🇩🇪'), 'DE');
    });

    test('the last flag wins when there are several', () {
      expect(countryCodeFromTag('Somewhere 🇺🇸🇯🇵'), 'JP');
    });

    test('no flag, no code', () {
      expect(countryCodeFromTag('EXIT-Tokyo, JP'), isNull);
      expect(countryCodeFromTag(''), isNull);
      expect(countryCodeFromTag('lowest'), isNull);
    });
  });

  group('flagCountryCode', () {
    test('the tag beats the probe', () {
      final node = OutboundInfo(
        tag: 'EXIT-Tokyo, JP🇯🇵',
        ipinfo: IpInfo(countryCode: 'US'),
      );
      expect(flagCountryCode(node), 'JP');
    });

    test('the display tag is tried when the raw tag ends in a hidden section', () {
      final node = OutboundInfo(tag: 'EXIT-Tokyo, JP🇯🇵§hide§x', tagDisplay: 'EXIT-Tokyo, JP🇯🇵');
      expect(flagCountryCode(node), 'JP');
    });

    test('falls back to the probe, then to nothing', () {
      expect(
        flagCountryCode(
          OutboundInfo(
            tag: 'EXIT-Tokyo',
            ipinfo: IpInfo(countryCode: 'JP'),
          ),
        ),
        'JP',
      );
      expect(flagCountryCode(OutboundInfo(tag: 'EXIT-Tokyo')), '');
    });

    test('a group uses the member it resolved to', () {
      final resolved = OutboundInfo(
        tag: 'lowest',
        isGroup: true,
        groupSelectedTag: 'EXIT-Tokyo, JP🇯🇵',
        ipinfo: IpInfo(countryCode: 'US'),
      );
      expect(flagCountryCode(resolved), 'JP');

      final unresolved = OutboundInfo(
        tag: 'balance',
        isGroup: true,
        groupSelectedTagDisplay: 'round-robin',
        ipinfo: IpInfo(countryCode: 'US'),
      );
      expect(flagCountryCode(unresolved), 'US');
    });
  });
}
