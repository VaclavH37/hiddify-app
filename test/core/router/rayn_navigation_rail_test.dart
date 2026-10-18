import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/rayn_navigation_rail.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';

void main() {
  const destinations = [
    RaynNavRailDestination(icon: Icons.shield_rounded, label: 'Home'),
    RaynNavRailDestination(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  Widget host({
    required bool extended,
    required ValueChanged<int> onTap,
    TextDirection textDirection = TextDirection.ltr,
  }) => MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, extensions: const [RaynPalette.dark]),
    home: Directionality(
      textDirection: textDirection,
      child: Scaffold(
        body: Row(
          children: [
            RaynNavigationRail(
              extended: extended,
              destinations: destinations,
              selectedIndex: 0,
              onDestinationSelected: onTap,
              footer: const Text('footer'),
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
    ),
  );

  // The test view is 800x600 logical at a device pixel ratio of 3.
  void setSystemPadding(WidgetTester tester, {double left = 0, double top = 0, double right = 0, double bottom = 0}) {
    final ratio = tester.view.devicePixelRatio;
    tester.view.padding = FakeViewPadding(
      left: left * ratio,
      top: top * ratio,
      right: right * ratio,
      bottom: bottom * ratio,
    );
    addTearDown(tester.view.resetPadding);
  }

  testWidgets('extended: 240 wide, labelled, footer at the foot, taps report the index', (tester) async {
    int? tapped;
    await tester.pumpWidget(host(extended: true, onTap: (i) => tapped = i));
    expect(tester.getSize(find.byType(RaynNavigationRail)).width, RaynNavigationRail.extendedWidth);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('footer'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('footer')).dy,
      greaterThan(tester.getBottomLeft(find.text('Settings')).dy),
      reason: 'the footer sits below the destinations',
    );
    await tester.tap(find.text('Settings'));
    expect(tapped, 1);
  });

  testWidgets('collapsed: 72 wide, icons only, footer still present', (tester) async {
    await tester.pumpWidget(host(extended: false, onTap: (_) {}));
    expect(tester.getSize(find.byType(RaynNavigationRail)).width, RaynNavigationRail.collapsedWidth);
    expect(find.text('Home'), findsNothing);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    expect(find.text('footer'), findsOneWidget);
  });

  // On an Android tablet the app draws behind the status bar and the gesture
  // handle; the rail's brand and footer used to sit under them.
  testWidgets('keeps the brand below the status bar and the footer above the navigation bar', (tester) async {
    setSystemPadding(tester, top: 24, bottom: 48);
    await tester.pumpWidget(host(extended: true, onTap: (_) {}));

    final rail = tester.getRect(find.byType(RaynNavigationRail));
    expect(rail.top, 0, reason: "the rail's colour still runs under the status bar");
    expect(tester.getTopLeft(find.byType(RaynWordmark)).dy, greaterThanOrEqualTo(24));
    expect(tester.getBottomLeft(find.text('footer')).dy, lessThanOrEqualTo(600 - 48));
  });

  testWidgets('clears only its outer edge, and widens by it so its content keeps its width', (tester) async {
    const inset = 30.0;
    const width = RaynNavigationRail.extendedWidth + inset;
    setSystemPadding(tester, left: inset, right: inset);

    // Left to right: the rail is on the left.
    await tester.pumpWidget(host(extended: true, onTap: (_) {}));
    expect(tester.getRect(find.byType(RaynNavigationRail)), const Rect.fromLTWH(0, 0, width, 600));
    expect(tester.getTopLeft(find.text('footer')).dx, greaterThanOrEqualTo(inset));
    expect(
      tester.getTopRight(find.text('footer')).dx,
      greaterThan(RaynNavigationRail.extendedWidth),
      reason: 'the inner edge takes no inset',
    );

    // Right to left: the rail is on the right.
    await tester.pumpWidget(host(extended: true, onTap: (_) {}, textDirection: TextDirection.rtl));
    expect(tester.getRect(find.byType(RaynNavigationRail)), const Rect.fromLTWH(800 - width, 0, width, 600));
    expect(tester.getTopRight(find.text('footer')).dx, lessThanOrEqualTo(800 - inset));
    expect(
      tester.getTopLeft(find.text('footer')).dx,
      lessThan(800 - width + inset),
      reason: 'the inner edge takes no inset',
    );
  });

  testWidgets('collapsed, the mark still fits beside a side inset', (tester) async {
    setSystemPadding(tester, left: 30);
    await tester.pumpWidget(host(extended: false, onTap: (_) {}));
    expect(tester.getSize(find.byType(RaynNavigationRail)).width, RaynNavigationRail.collapsedWidth + 30);
    expect(tester.takeException(), isNull);
  });
}
