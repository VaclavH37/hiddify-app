import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/active/proxy_snapshot_notifier.dart';
import 'package:hiddify/features/proxy/active/selected_location_notifier.dart';

void main() {
  group('ProxySnapshot', () {
    final snap = ProxySnapshot(
      groupTag: 'select',
      selectedTag: 'lowest',
      items: const [
        SnapshotItem(
          tag: 'lowest',
          tagDisplay: 'lowest',
          type: 'urltest',
          isGroup: true,
          groupSelectedTagDisplay: 'EXIT-JP-TOKYO-02',
          countryCode: 'JP',
          city: 'Tokyo',
          region: '',
          org: '',
        ),
        SnapshotItem(
          tag: 'EXIT-SK-SEOUL-01',
          tagDisplay: 'EXIT-SK-SEOUL-01',
          type: 'vless',
          isGroup: false,
          groupSelectedTagDisplay: '',
          countryCode: 'KR',
          city: 'Seoul',
          region: '',
          org: 'Hetzner',
        ),
      ],
    );

    test('encode/decode round-trips all fields including geo + resolved member', () {
      final decoded = ProxySnapshot.tryDecode(snap.encode())!;
      expect(decoded.groupTag, 'select');
      expect(decoded.selectedTag, 'lowest');
      expect(decoded.items.length, 2);
      expect(decoded.items[0].isGroup, isTrue);
      expect(decoded.items[0].groupSelectedTagDisplay, 'EXIT-JP-TOKYO-02');
      expect(decoded.items[0].city, 'Tokyo');
      expect(decoded.items[1].tag, 'EXIT-SK-SEOUL-01');
      expect(decoded.items[1].countryCode, 'KR');
      expect(decoded.items[1].org, 'Hetzner');
    });

    test('tryDecode returns null for null, garbage, or empty item list', () {
      expect(ProxySnapshot.tryDecode(null), isNull);
      expect(ProxySnapshot.tryDecode('not json'), isNull);
      expect(ProxySnapshot.tryDecode('{"g":"select","s":"","i":[]}'), isNull);
    });

    test('toOutboundGroup preserves tags, selection, group split, geo, and resolved member', () {
      final group = snap.toOutboundGroup();
      expect(group.tag, 'select');
      expect(group.selected, 'lowest');

      final groups = group.items.where((e) => e.isGroup).toList();
      final servers = group.items.where((e) => !e.isGroup).toList();
      expect(groups.single.tag, 'lowest');
      expect(groups.single.groupSelectedTagDisplay, 'EXIT-JP-TOKYO-02');
      expect(groups.single.ipinfo.city, 'Tokyo');
      expect(servers.single.tag, 'EXIT-SK-SEOUL-01');
      expect(servers.single.ipinfo.countryCode, 'KR');
    });
  });

  group('SelectedLocation', () {
    test('encode/decode round-trips displayName, country, and auto-selected flag', () {
      const loc = SelectedLocation(displayName: 'Tokyo, JP', countryCode: 'JP', isAutoSelected: true);
      final decoded = SelectedLocation.tryDecode(loc.encode())!;
      expect(decoded.displayName, 'Tokyo, JP');
      expect(decoded.countryCode, 'JP');
      expect(decoded.isAutoSelected, isTrue);
      expect(decoded, loc);
    });

    test('a specific exit is not auto-selected', () {
      const loc = SelectedLocation(displayName: 'Seoul, SK', countryCode: 'KR', isAutoSelected: false);
      expect(SelectedLocation.tryDecode(loc.encode())!.isAutoSelected, isFalse);
    });

    test('tryDecode returns null for null, empty name, or garbage', () {
      expect(SelectedLocation.tryDecode(null), isNull);
      expect(SelectedLocation.tryDecode('{"n":"","c":"KR"}'), isNull);
      expect(SelectedLocation.tryDecode('garbage'), isNull);
    });
  });
}
