import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/connection/clock/model/clock_skew.dart';
import 'package:hiddify/features/connection/clock/notifier/clock_skew_notifier.dart';
import 'package:hiddify/features/connection/clock/widget/clock_banner.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The home-page "device time is wrong" warning.
void main() {
  final t = AppLocale.en.buildSync();

  Future<_FakeClockSkew> pump(WidgetTester tester, {required bool canOpenSettings, required bool apple}) async {
    final notifier = _FakeClockSkew(const ClockIssue(skew: Duration(minutes: 2)));
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => t),
        clockSkewNotifierProvider.overrideWith(() => notifier),
      ],
    );
    addTearDown(container.dispose);
    await container.read(translationsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
          home: Scaffold(
            body: Center(
              child: ClockBanner(canOpenSettings: canOpenSettings, apple: apple),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  testWidgets('Android and Windows: says what is wrong and offers the settings page', (tester) async {
    await pump(tester, canOpenSettings: true, apple: false);
    expect(find.text("Your device's time is wrong"), findsOneWidget);
    expect(find.text("Rayn VPN may not connect until it's correct. Turn on automatic date and time."), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open date and time settings'), findsOneWidget);
  });

  testWidgets('iPhone: the steps instead of a button, since iOS has no link to them', (tester) async {
    await pump(tester, canOpenSettings: false, apple: true);
    expect(find.textContaining('Settings > General > Date & Time'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('the close button dismisses the warning', (tester) async {
    final notifier = await pump(tester, canOpenSettings: true, apple: false);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(notifier.dismissals, 1);
  });
}

class _FakeClockSkew extends ClockSkewNotifier {
  _FakeClockSkew(this.initial);

  final ClockIssue? initial;
  int dismissals = 0;

  @override
  ClockIssue? build() => initial;

  @override
  void dismiss() => dismissals++;
}
