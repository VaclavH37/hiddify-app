import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/home/widget/sidebar_status.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: ThemeData(brightness: Brightness.dark, extensions: const [RaynPalette.dark]),
    home: Scaffold(body: SizedBox(width: 240, child: child)),
  );

  testWidgets('connected and extended: dot, word, speeds, total', (tester) async {
    await tester.pumpWidget(
      host(
        const SidebarStatusView(
          extended: true,
          protected: true,
          label: 'Protected',
          upload: '1 KB/s',
          download: '2 KB/s',
          totalLabel: 'Total traffic',
          total: '20 KB',
        ),
      ),
    );
    expect(find.text('Protected'), findsOneWidget);
    expect(find.text('1 KB/s'), findsOneWidget);
    expect(find.text('2 KB/s'), findsOneWidget);
    expect(find.text('Total traffic 20 KB'), findsOneWidget);
  });

  testWidgets('disconnected: the word alone, no traffic lines', (tester) async {
    await tester.pumpWidget(
      host(
        const SidebarStatusView(extended: true, protected: false, label: 'Not protected', totalLabel: 'Total traffic'),
      ),
    );
    expect(find.text('Not protected'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(find.textContaining('Total traffic'), findsNothing);
  });

  testWidgets('collapsed: only the dot, still labelled', (tester) async {
    await tester.pumpWidget(
      host(const SidebarStatusView(extended: false, protected: true, label: 'Protected', totalLabel: 'Total traffic')),
    );
    expect(find.text('Protected'), findsNothing);
    expect(find.bySemanticsLabel('Protected'), findsOneWidget);
  });
}
