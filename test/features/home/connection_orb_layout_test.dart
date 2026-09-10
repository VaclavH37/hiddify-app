import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';

/// The orb has to lay out in every state, in the constraints the home canvas
/// actually hands it. The connecting ring once broke this: it was an
/// OverflowBox, which sizes itself to whatever its parent allows, and the
/// canvas allows the orb the whole page (loose) or, through the column, an
/// unbounded height. The first tap on the button then failed the page's layout
/// and left the label at the origin with nothing else drawn.
///
/// The widget's box is the circle plus the label under it, so its width is
/// whichever of the two is wider; what must never change is the circle.
void main() {
  const circle = Key('home_connection_button');
  const states = {
    'idle': OrbState(tint: OrbTint.disconnected, label: 'Tap to connect', ring: false, enabled: true),
    'connecting': OrbState(tint: OrbTint.connecting, label: 'Connecting…', ring: true, enabled: false),
    'connected': OrbState(tint: OrbTint.connected, label: 'Connected', ring: false, enabled: true, isConnected: true),
    'error': OrbState(
      tint: OrbTint.error,
      label: 'Unexpected connection error with a long explanation',
      ring: false,
      enabled: true,
    ),
  };

  Widget host(Widget orb, {required bool unboundedHeight}) {
    // The two constraint shapes the canvas produces: loose to the page size,
    // and a column (unbounded height) with the orb as its only child.
    final body = unboundedHeight ? Column(mainAxisSize: MainAxisSize.min, children: [orb]) : Center(child: orb);
    return MaterialApp(home: Scaffold(body: body));
  }

  for (final unbounded in [false, true]) {
    for (final entry in states.entries) {
      testWidgets('${entry.key} orb lays out (unbounded height: $unbounded)', (tester) async {
        await tester.pumpWidget(
          host(
            ConnectionOrb(key: const Key('orb'), state: entry.value, onTap: () {}),
            unboundedHeight: unbounded,
          ),
        );
        // Let the ring's switcher settle without waiting on the indeterminate
        // spinner, which never does.
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        expect(tester.getSize(find.byKey(circle)), const Size(ConnectionButton.diameter, ConnectionButton.diameter));

        final box = tester.getRect(find.byKey(const Key('orb')));
        expect(box.width, greaterThanOrEqualTo(ConnectionButton.diameter));
        expect(box.width, lessThanOrEqualTo(260), reason: 'the label is capped so the box never balloons');
        expect(box.height, greaterThan(ConnectionButton.diameter), reason: 'the label is part of the box');
        expect(box.height, lessThan(ConnectionButton.diameter + 120), reason: 'circle, gap, at most two lines');
        // The circle sits centred in the box, so centring the box centres it.
        expect(tester.getCenter(find.byKey(circle)).dx, closeTo(box.center.dx, 0.5));
      });
    }
  }

  testWidgets('the ring appears outside the circle and leaves it where it was', (tester) async {
    await tester.pumpWidget(
      host(ConnectionOrb(key: const Key('orb'), state: states['idle']!, onTap: () {}), unboundedHeight: true),
    );
    final before = tester.getRect(find.byKey(circle));

    await tester.pumpWidget(
      host(ConnectionOrb(key: const Key('orb'), state: states['connecting']!, onTap: () {}), unboundedHeight: true),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    final ring = tester.getRect(find.byType(CircularProgressIndicator));
    final after = tester.getRect(find.byKey(circle));
    expect(after.top, before.top);
    expect(after.size, before.size);
    // A few pixels wider than the circle on every side, concentric with it.
    expect(ring.width, greaterThan(after.width));
    expect(ring.width, lessThan(after.width + 24));
    expect(ring.center.dx, closeTo(after.center.dx, 0.5));
    expect(ring.center.dy, closeTo(after.center.dy, 0.5));
  });
}
