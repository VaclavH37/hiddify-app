import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/disclosure/widget/disclosure_scaffold.dart';

/// The consent gate's load-bearing properties: the system back button does
/// nothing, and the affirmative action is always on screen without scrolling.
void main() {
  Widget host() {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
      home: DisclosureScaffold(
        title: 'How it works',
        sections: [for (var i = 0; i < 8; i++) DisclosureSection(title: 'Section $i', body: 'Body ' * 40)],
        consent: 'By tapping you agree.',
        privacyLabel: 'Privacy',
        termsLabel: 'Terms',
        agreeLabel: 'Agree',
        onAgree: () {},
        declineLabel: 'Decline',
        onDecline: () {},
      ),
    );
  }

  testWidgets('back is a no-op and the actions stay pinned under a long body', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());

    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

    final agree = find.widgetWithText(FilledButton, 'Agree');
    expect(find.descendant(of: find.byType(SingleChildScrollView), matching: agree), findsNothing);
    expect(tester.getRect(agree).bottom, lessThanOrEqualTo(800));

    // The body is longer than the screen: it scrolls, the button does not move.
    final before = tester.getRect(agree).top;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(tester.getRect(agree).top, before);
  });
}
