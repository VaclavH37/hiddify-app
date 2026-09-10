import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_section_header.dart';
import 'package:hiddify/core/widget/rayn_settings_group.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';

/// The settings list primitives, as a system: one surface per group, rows of
/// one height, sentence-case headers, no ring around icons.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, extensions: const [RaynPalette.dark]),
    home: Scaffold(body: ListView(children: [child])),
  );

  testWidgets('every row in a group is as tall as the tallest', (tester) async {
    await tester.pumpWidget(
      host(
        const RaynSettingsGroup(
          children: [
            RaynSettingsTile(key: Key('plain'), leading: Icons.language, title: 'Language'),
            RaynSettingsTile(
              key: Key('tall'),
              leading: Icons.memory,
              title: 'Memory limit',
              subtitle: 'Enable if you are seeing out-of-memory errors or frequent crashes',
            ),
            RaynSettingsTile(key: Key('plain2'), leading: Icons.flag, title: 'Check IP'),
          ],
        ),
      ),
    );
    final tall = tester.getSize(find.byKey(const Key('tall'))).height;
    expect(tall, greaterThan(RaynSettingsTile.minHeight), reason: 'the subtitle makes this row the tallest');
    expect(tester.getSize(find.byKey(const Key('plain'))).height, tall);
    expect(tester.getSize(find.byKey(const Key('plain2'))).height, tall);
    // Three rows, two hairlines between them.
    expect(tester.getSize(find.byType(RaynSettingsGroup)).height, 3 * tall + 2);
  });

  testWidgets('a row that hides itself takes no space and no separator', (tester) async {
    await tester.pumpWidget(
      host(
        const RaynSettingsGroup(
          children: [
            RaynSettingsTile(key: Key('a'), leading: Icons.language, title: 'Language'),
            SizedBox.shrink(),
            RaynSettingsTile(key: Key('b'), leading: Icons.flag, title: 'Check IP'),
          ],
        ),
      ),
    );
    final row = tester.getSize(find.byKey(const Key('a'))).height;
    expect(tester.getSize(find.byType(RaynSettingsGroup)).height, 2 * row + 1);
  });

  testWidgets('a row is at least a finger tall and its icon has no ring', (tester) async {
    await tester.pumpWidget(
      host(
        const RaynSettingsGroup(
          children: [RaynSettingsTile(leading: Icons.language, title: 'Language')],
        ),
      ),
    );
    expect(tester.getSize(find.byType(RaynSettingsTile)).height, greaterThanOrEqualTo(RaynSettingsTile.minHeight));
    // The old tile wrapped the icon in a bordered circle. Nothing decorated
    // sits between the row and its icon now.
    final decorated = find.descendant(of: find.byType(RaynSettingsTile), matching: find.byType(DecoratedBox));
    expect(decorated, findsNothing);
  });

  testWidgets('a picker row shows its value and a chevron', (tester) async {
    await tester.pumpWidget(
      host(
        const RaynSettingsGroup(
          children: [
            RaynSettingsTile(leading: Icons.language, title: 'Language', trailing: RaynSettingsValue('English')),
          ],
        ),
      ),
    );
    expect(find.text('English'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('a section header keeps its case', (tester) async {
    await tester.pumpWidget(host(const RaynSectionHeader('Account deletion')));
    expect(find.text('Account deletion'), findsOneWidget);
    expect(find.text('ACCOUNT DELETION'), findsNothing);
  });
}
