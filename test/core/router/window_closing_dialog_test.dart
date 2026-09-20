import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/widgets/window_closing_dialog.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The desktop "window closed" question. It is about the VPN, not the window:
/// it names what each choice does to the connection, keeping the app running
/// is the primary, and the other button says "Exit" because that is what it
/// does. The test host is not macOS, so the copy is the system-tray wording.
void main() {
  final t = AppLocale.en.buildSync();

  Future<({ProviderContainer container, _FakeWindow window})> open(
    WidgetTester tester, {
    ConnectionStatus status = const ConnectionStatus.disconnected(),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final window = _FakeWindow();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => t),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
        connectionNotifierProvider.overrideWith(() => _FixedConnection(status)),
        windowNotifierProvider.overrideWith(() => window),
      ],
    );
    addTearDown(container.dispose);
    // The dialog reads both synchronously, as the app does after bootstrap.
    await container.read(sharedPreferencesProvider.future);
    await container.read(translationsProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const WindowClosingDialog()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (container: container, window: window);
  }

  testWidgets('asks about the VPN and names both choices; keeping it running is the primary', (tester) async {
    await open(tester);

    expect(find.text('Keep Rayn VPN running?'), findsOneWidget);
    expect(find.text('It stays in the system tray. Exit closes it completely.'), findsOneWidget);
    expect(find.text('Remember my choice'), findsOneWidget);

    final primary = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Keep running'));
    expect(primary.autofocus, isTrue, reason: 'Enter keeps the VPN running');
    expect(find.widgetWithText(TextButton, 'Exit'), findsOneWidget);

    expect(find.textContaining('Hide or exit'), findsNothing);
    expect(find.text('Close'), findsNothing, reason: 'the button that quits no longer says "Close"');
  });

  testWidgets('while connected it says the connection stays, and that exiting disconnects', (tester) async {
    await open(tester, status: const ConnectionStatus.connected());

    expect(find.text('It stays connected in the system tray. Exit disconnects and closes it.'), findsOneWidget);
  });

  testWidgets('"Keep running" hides the window, closes the dialog and remembers nothing unasked', (tester) async {
    final h = await open(tester);
    await tester.tap(find.text('Keep running'));
    await tester.pumpAndSettle();

    expect(h.window.calls, ['hide']);
    expect(find.text('Keep Rayn VPN running?'), findsNothing);
    expect(h.container.read(Preferences.actionAtClose), ActionsAtClosing.ask);
  });

  testWidgets('with the box ticked, "Keep running" is remembered', (tester) async {
    final h = await open(tester);
    await tester.tap(find.text('Remember my choice'));
    await tester.pump();
    await tester.tap(find.text('Keep running'));
    await tester.pumpAndSettle();

    expect(h.window.calls, ['hide']);
    expect(h.container.read(Preferences.actionAtClose), ActionsAtClosing.hide);
  });

  testWidgets('with the box ticked, "Exit" is remembered and the app exits', (tester) async {
    final h = await open(tester);
    await tester.tap(find.text('Remember my choice'));
    await tester.pump();
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(h.window.calls, ['exit']);
    expect(h.container.read(Preferences.actionAtClose), ActionsAtClosing.exit);
  });

  test('the sentence follows the connection and where the platform keeps a background app', () {
    final copy = t.dialogs.windowClosing;
    expect(windowClosingBody(t, connected: true, menuBar: false), copy.connectedTray);
    expect(windowClosingBody(t, connected: true, menuBar: true), copy.connectedMenuBar);
    expect(windowClosingBody(t, connected: false, menuBar: false), copy.idleTray);
    expect(windowClosingBody(t, connected: false, menuBar: true), copy.idleMenuBar);
  });

  test("Settings names a remembered choice in the dialog's own words", () {
    expect(ActionsAtClosing.hide.present(t), 'Keep running');
    expect(ActionsAtClosing.exit.present(t), 'Exit');
  });
}

class _FixedConnection extends ConnectionNotifier {
  _FixedConnection(this.status);

  final ConnectionStatus status;

  @override
  Stream<ConnectionStatus> build() => Stream.value(status);
}

class _FakeWindow extends WindowNotifier {
  final List<String> calls = [];

  @override
  Future<void> build() async {}

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  Future<void> exit() async => calls.add('exit');
}
