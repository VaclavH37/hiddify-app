import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';

/// Pins the de-glass decision: surfaces are opaque, unblurred, and borderless
/// on dark. A blur or a dark-mode hairline creeping back in would pass every
/// behavioural test in the suite, so this one looks at the decoration itself.
void main() {
  Widget host(Brightness brightness, Widget child) {
    final palette = brightness == Brightness.dark ? RaynPalette.dark : RaynPalette.light;
    return MaterialApp(
      theme: ThemeData(brightness: brightness, extensions: [palette]),
      home: Scaffold(body: Center(child: child)),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(RaynSurface), matching: find.byType(DecoratedBox)),
    );
    return box.decoration as BoxDecoration;
  }

  for (final brightness in Brightness.values) {
    testWidgets('$brightness: no backdrop blur, opaque fill', (tester) async {
      await tester.pumpWidget(host(brightness, const RaynSurface(child: SizedBox(width: 80, height: 40))));
      expect(find.byType(BackdropFilter), findsNothing);
      final decoration = decorationOf(tester);
      expect(decoration.color!.a, 1.0, reason: 'depth is tone, not transparency');
      expect(decoration.boxShadow, isNull, reason: 'a list row does not float');
    });
  }

  testWidgets('dark: no hairline', (tester) async {
    await tester.pumpWidget(host(Brightness.dark, const RaynSurface(child: SizedBox(width: 80, height: 40))));
    expect(decorationOf(tester).border, isNull);
  });

  testWidgets('light: a hairline, because cream on cream has no tone to spare', (tester) async {
    await tester.pumpWidget(host(Brightness.light, const RaynSurface(child: SizedBox(width: 80, height: 40))));
    expect(decorationOf(tester).border, isNotNull);
  });

  testWidgets('elevated: one neutral shadow', (tester) async {
    await tester.pumpWidget(
      host(Brightness.dark, const RaynSurface(elevated: true, child: SizedBox(width: 80, height: 40))),
    );
    final shadows = decorationOf(tester).boxShadow!;
    expect(shadows, hasLength(1));
    expect(shadows.single.color, RaynPalette.dark.shadow);
  });

  test('the dark surface is a visible step above the page', () {
    // Roughly twelve levels in each channel; four, the previous value, was not
    // something anyone could see.
    final page = RaynPalette.dark.pageBackground;
    final surface = RaynPalette.dark.groupFill;
    expect((surface.r - page.r) * 255, greaterThanOrEqualTo(10));
    expect((surface.g - page.g) * 255, greaterThanOrEqualTo(10));
    expect((surface.b - page.b) * 255, greaterThanOrEqualTo(8));
  });
}
