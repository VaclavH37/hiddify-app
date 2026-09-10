import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_option_list.dart';

void main() {
  testWidgets('marks the current option and reports the one tapped', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, extensions: const [RaynPalette.dark]),
        home: Scaffold(
          body: RaynOptionList<String>(
            title: 'Theme mode',
            options: const ['System default', 'Light mode', 'Dark mode'],
            selected: 'Dark mode',
            getTitle: (option) => option,
            onSelected: (option) => picked = option,
          ),
        ),
      ),
    );

    expect(find.text('Theme mode'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // The check sits on the selected row, not on the others.
    final check = tester.getCenter(find.byIcon(Icons.check_rounded));
    final dark = tester.getCenter(find.text('Dark mode'));
    expect((check.dy - dark.dy).abs(), lessThan(1));

    await tester.tap(find.text('Light mode'));
    expect(picked, 'Light mode');
  });
}
