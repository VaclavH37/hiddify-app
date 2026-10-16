import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/local_routing/model/egress_routing.dart';

/// The core's JSON (hiddify-core v2/config/egress_routing.go, whose test pins
/// the same field names) and what the app derives from it.
void main() {
  Object? decode(String json) => jsonDecode(json);

  group('EgressRouting.fromJson', () {
    test('reads a checked answer', () {
      final routing = EgressRouting.fromJson(
        decode(
          '{"checked":true,"index":4,"alias":"Wi-Fi","forwarding":true,"forwarding6":true,"weak_host_send":false}',
        ),
      );
      expect(routing, const EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: true, forwarding6: true));
    });

    test('keeps a localised adapter name as given', () {
      final routing = EgressRouting.fromJson(
        decode(
          '{"checked":true,"index":7,"alias":"WLAN 2","forwarding":false,"forwarding6":false,"weak_host_send":true}',
        ),
      );
      expect(routing?.alias, 'WLAN 2');
      expect(routing?.weakHostSend, isTrue);
    });

    test('an unchecked answer means nothing to report', () {
      expect(
        EgressRouting.fromJson(
          decode(
            '{"checked":false,"index":0,"alias":"","forwarding":false,"forwarding6":false,"weak_host_send":false}',
          ),
        ),
        isNull,
      );
      expect(EgressRouting.fromJson(decode('{"checked":false}')), isNull);
    });

    test('anything that is not what the core writes is ignored', () {
      expect(EgressRouting.fromJson(null), isNull);
      expect(EgressRouting.fromJson(decode('[]')), isNull);
      expect(EgressRouting.fromJson(decode('{"checked":true,"alias":"Wi-Fi","forwarding":true}')), isNull);
      expect(EgressRouting.fromJson(decode('{"checked":true,"index":0,"alias":"Wi-Fi","forwarding":true}')), isNull);
      expect(EgressRouting.fromJson(decode('{"checked":true,"index":4,"alias":"","forwarding":true}')), isNull);
      expect(EgressRouting.fromJson(decode('{"checked":true,"index":4,"alias":"Wi-Fi","forwarding":"yes"}')), isNull);
    });
  });

  test('only IPv4 forwarding blocks the tunnel', () {
    expect(const EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: true).blocksTunnel, isTrue);
    expect(const EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: false, forwarding6: true).blocksTunnel, isFalse);
    expect(const EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: false, weakHostSend: true).blocksTunnel, isFalse);
  });

  test('the fix command names the adapter by index, so it needs no quoting', () {
    expect(
      const EgressRouting(index: 12, alias: 'Wi-Fi "home"', forwarding: true).fixCommand,
      'netsh interface ipv4 set interface 12 forwarding=disabled',
    );
  });
}
