import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The picker row's latency column. The core reports a failed probe as 65535
/// and an unprobed exit as 0; the row used to show nothing for both, so the
/// dead exit "Fastest server" kept picking looked merely unmeasured.
void main() {
  Widget host(OutboundInfo proxy) => ProviderScope(
    overrides: [translationsProvider.overrideWith((ref) => AppLocale.en.buildSync())],
    child: MaterialApp(
      theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
      home: Consumer(
        builder: (context, ref, _) => ref.watch(translationsProvider).hasValue
            ? Scaffold(body: ProxyTile(proxy, selected: false, onTap: () {}))
            : const SizedBox.shrink(),
      ),
    ),
  );

  Future<void> pumpTile(WidgetTester tester, OutboundInfo proxy) async {
    await tester.pumpWidget(host(proxy));
    await tester.pump();
  }

  testWidgets('a failed probe reads "No response" in the danger colour', (tester) async {
    await pumpTile(tester, OutboundInfo(tag: 'EXIT-Nowhere', urlTestDelay: 65535));
    final text = tester.widget<Text>(find.text('No response'));
    expect(text.style?.color, RaynPalette.light.danger);
    expect(find.textContaining(' ms'), findsNothing);
  });

  testWidgets('an unprobed exit shows no latency at all', (tester) async {
    await pumpTile(tester, OutboundInfo(tag: 'EXIT-Nowhere'));
    expect(find.text('No response'), findsNothing);
    expect(find.textContaining(' ms'), findsNothing);
  });

  testWidgets('a measured exit shows its latency', (tester) async {
    await pumpTile(tester, OutboundInfo(tag: 'EXIT-Nowhere', urlTestDelay: 120));
    expect(find.text('120 ms'), findsOneWidget);
    expect(find.text('No response'), findsNothing);
  });

  testWidgets('a group row never shows a latency, even with the sentinel', (tester) async {
    await pumpTile(tester, OutboundInfo(tag: 'lowest', tagDisplay: 'lowest', isGroup: true, urlTestDelay: 65535));
    expect(find.text('Fastest server'), findsOneWidget);
    expect(find.text('No response'), findsNothing);
  });
}
