import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/unique_keys_layout.dart';

/// The connect orb's two switchers (its ring and its label) can flip A, B, A
/// faster than their fade: "Connecting…", "Connected", then "Connecting…"
/// again when a reconnect starts.
Widget _switcher(String key, {AnimatedSwitcherLayoutBuilder? layout}) => Directionality(
  textDirection: TextDirection.ltr,
  child: AnimatedSwitcher(
    duration: const Duration(milliseconds: 300),
    layoutBuilder: layout ?? AnimatedSwitcher.defaultLayoutBuilder,
    child: Text(key, key: ValueKey(key)),
  ),
);

Future<void> _flip(WidgetTester tester, {AnimatedSwitcherLayoutBuilder? layout}) async {
  await tester.pumpWidget(_switcher('connecting', layout: layout));
  await tester.pump(const Duration(milliseconds: 400));
  // Back and forth faster than the switch takes: two "connecting" fade out at once.
  for (final key in ['connected', 'connecting', 'connected']) {
    await tester.pumpWidget(_switcher(key, layout: layout));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a child back within the switch breaks the default layout', (tester) async {
    await _flip(tester);
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('it does not break the unique keys layout', (tester) async {
    await _flip(tester, layout: uniqueKeysLayout());
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.text('connected'), findsOneWidget);
    expect(find.text('connecting'), findsNothing);
  });
}
