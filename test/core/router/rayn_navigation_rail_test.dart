import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/router/adaptive_layout/rayn_navigation_rail.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';

void main() {
  const destinations = [
    RaynNavRailDestination(icon: Icons.shield_rounded, label: 'Home'),
    RaynNavRailDestination(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  Widget host({required bool extended, required ValueChanged<int> onTap}) => MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, extensions: const [RaynPalette.dark]),
    home: Scaffold(
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
  );

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
}
