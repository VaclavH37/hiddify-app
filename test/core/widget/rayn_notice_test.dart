import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_notice.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';

/// The tone lives in the icon only: the surface underneath is the plain
/// surface, so a warning and an explainer sit on the same card.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, extensions: const [RaynPalette.dark]),
      home: Scaffold(body: Center(child: child)),
    );
  }

  Color iconColour(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon)).color!;

  testWidgets('each tone tints its icon from the palette', (tester) async {
    await tester.pumpWidget(host(const RaynNotice(message: 'm')));
    expect(iconColour(tester), RaynPalette.dark.accentText);

    await tester.pumpWidget(host(const RaynNotice(message: 'm', tone: RaynNoticeTone.warning)));
    expect(iconColour(tester), RaynPalette.dark.warning);

    await tester.pumpWidget(host(const RaynNotice(message: 'm', tone: RaynNoticeTone.danger)));
    expect(iconColour(tester), RaynPalette.dark.danger);
  });

  testWidgets('the surface is the plain surface, whatever the tone', (tester) async {
    await tester.pumpWidget(host(const RaynNotice(message: 'm', tone: RaynNoticeTone.danger)));
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(RaynSurface), matching: find.byType(DecoratedBox)),
    );
    expect((box.decoration as BoxDecoration).color, RaynPalette.dark.groupFill);
  });

  testWidgets('a custom icon and actions render', (tester) async {
    await tester.pumpWidget(
      host(
        RaynNotice(
          message: 'Payment is processing',
          icon: Icons.hourglass_top_rounded,
          actions: [TextButton(onPressed: () {}, child: const Text('Restore'))],
        ),
      ),
    );
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
  });
}
