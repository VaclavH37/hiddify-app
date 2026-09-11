import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// The picker's alphabetical order groups by country and reads by name
/// within one; exits without a country go last.
void main() {
  OutboundInfo node(String tag, {String probe = ''}) => OutboundInfo(
    tag: tag,
    ipinfo: IpInfo(countryCode: probe),
  );

  test('country code first, then name', () {
    final items = [
      node('EXIT-Tokyo, JP🇯🇵'),
      node('EXIT-Amsterdam, NL🇳🇱'),
      node('EXIT-Osaka, JP🇯🇵'),
      node('EXIT-Dallas, US🇺🇸'),
      node('EXIT-Berlin, DE🇩🇪'),
    ]..sort(compareByCountryThenName);
    expect(items.map((i) => i.tag), [
      'EXIT-Berlin, DE🇩🇪',
      'EXIT-Osaka, JP🇯🇵',
      'EXIT-Tokyo, JP🇯🇵',
      'EXIT-Amsterdam, NL🇳🇱',
      'EXIT-Dallas, US🇺🇸',
    ]);
  });

  test('a node with no country sorts last; the probe still counts as a country', () {
    final items = [node('EXIT-Nowhere'), node('EXIT-Probed', probe: 'FR'), node('EXIT-Tokyo, JP🇯🇵')]
      ..sort(compareByCountryThenName);
    expect(items.map((i) => i.tag), ['EXIT-Probed', 'EXIT-Tokyo, JP🇯🇵', 'EXIT-Nowhere']);
  });

  test('names compare without case', () {
    final items = [node('EXIT-b, JP🇯🇵'), node('EXIT-A, JP🇯🇵'), node('EXIT-C, JP🇯🇵')]
      ..sort(compareByCountryThenName);
    expect(items.map((i) => i.tag), ['EXIT-A, JP🇯🇵', 'EXIT-b, JP🇯🇵', 'EXIT-C, JP🇯🇵']);
  });
}
