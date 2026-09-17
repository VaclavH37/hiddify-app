import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// The picker's two orders. Alphabetical groups by country and reads by name
/// within one; exits without a country go last. By latency reads measured
/// exits fastest first, then unprobed ones, then the exits whose probe
/// failed: the core reports a failed probe as 65535 and an unprobed exit as
/// 0, and neither is a measurement.
void main() {
  OutboundInfo node(String tag, {String probe = '', int delay = 0}) => OutboundInfo(
    tag: tag,
    ipinfo: IpInfo(countryCode: probe),
    urlTestDelay: delay,
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

  group('by latency', () {
    test('measured fastest first, then unprobed, then failed', () {
      final items = [
        node('failed', delay: 65535),
        node('slow', delay: 320),
        node('unprobed'),
        node('fast', delay: 110),
        node('failed-too', delay: 65000),
      ]..sort(compareByDelay);
      expect(items.map((i) => i.tag), ['fast', 'slow', 'unprobed', 'failed', 'failed-too']);
    });

    test('the dead exit the bug picked sorts last, not first', () {
      final items = [node('live', delay: 250), node('dead', delay: 65535)]..sort(compareByDelay);
      expect(items.first.tag, 'live');
    });

    test('two unmeasured exits of one class compare equal, so the order is stable', () {
      expect(compareByDelay(node('a'), node('b')), 0);
      expect(compareByDelay(node('a', delay: 65535), node('b', delay: 65535)), 0);
      expect(compareByDelay(node('a', delay: 200), node('b', delay: 200)), 0);
    });

    test('the classes', () {
      expect(delayClassOf(0), DelayClass.untested);
      expect(delayClassOf(-1), DelayClass.untested);
      expect(delayClassOf(1), DelayClass.measured);
      expect(delayClassOf(64999), DelayClass.measured);
      expect(delayClassOf(65000), DelayClass.failed);
      expect(delayClassOf(65535), DelayClass.failed);
    });
  });
}
