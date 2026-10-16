import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/local_routing/data/egress_routing_probe.dart';

/// The probe never throws into the app: a core it cannot reach, or one built
/// before the export existed, reads as "nothing to report", and is not retried.
void main() {
  test('a library that cannot be opened reads as nothing, once', () {
    var opens = 0;
    final probe = FfiEgressRoutingProbe(() {
      opens++;
      throw ArgumentError('Failed to load dynamic library');
    });
    expect(probe.read(), isNull);
    expect(probe.read(), isNull);
    expect(opens, 1);
  });

  test('a library without the export (an older core) reads as nothing, once', () {
    var opens = 0;
    final probe = FfiEgressRoutingProbe(() {
      opens++;
      return DynamicLibrary.executable();
    });
    expect(probe.read(), isNull);
    expect(probe.read(), isNull);
    expect(opens, 1);
  });

  test('the stand-in for other platforms reports nothing', () {
    expect(const NoEgressRoutingProbe().read(), isNull);
  });
}
