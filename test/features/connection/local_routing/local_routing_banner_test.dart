import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/connection/local_routing/model/egress_routing.dart';
import 'package:hiddify/features/connection/local_routing/model/local_routing_tracker.dart';
import 'package:hiddify/features/connection/local_routing/notifier/local_routing_notifier.dart';
import 'package:hiddify/features/connection/local_routing/widget/local_routing_banner.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

/// The home-page warning and its "How to fix" dialog.
void main() {
  final t = AppLocale.en.buildSync();
  const routing = EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: true);
  const issue = LocalRoutingIssue(routing: routing);

  Future<({_FakeLocalRouting notifier, _RecordingToasts toasts})> pump(WidgetTester tester) async {
    final notifier = _FakeLocalRouting(issue);
    final toasts = _RecordingToasts();
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => t),
        localRoutingNotifierProvider.overrideWith(() => notifier),
        inAppNotificationControllerProvider.overrideWithValue(toasts),
      ],
    );
    addTearDown(container.dispose);
    await container.read(translationsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
          home: const Scaffold(
            body: Center(child: LocalRoutingBanner(issue: issue)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (notifier: notifier, toasts: toasts);
  }

  testWidgets('says what is wrong and names the adapter', (tester) async {
    await pump(tester);
    expect(find.text("Rayn VPN can't reach the internet"), findsOneWidget);
    expect(
      find.text(
        "IP routing is turned on for Wi-Fi, so Windows sends Rayn VPN's own connections back into the tunnel and nothing gets through.",
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'How to fix'), findsOneWidget);
  });

  testWidgets('How to fix leads with removing the cause, then the command by index', (tester) async {
    await pump(tester);
    await tester.tap(find.text('How to fix'));
    await tester.pumpAndSettle();

    expect(find.text('Turn off IP routing on Wi-Fi'), findsOneWidget);
    final dialog = find.byType(LocalRoutingHelpDialog);
    expect(find.descendant(of: dialog, matching: find.textContaining('Mobile hotspot')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.textContaining('Incoming Connections')), findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('netsh interface ipv4 set interface 4 forwarding=disabled')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
  });

  testWidgets('Copy puts the command on the clipboard and says so', (tester) async {
    final pumped = await pump(tester);
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.tap(find.text('How to fix'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(clipboard, 'netsh interface ipv4 set interface 4 forwarding=disabled');
    expect(pumped.toasts.success, ['Command copied']);
  });

  testWidgets('the close button dismisses the warning', (tester) async {
    final pumped = await pump(tester);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(pumped.notifier.dismissals, 1);
  });
}

class _FakeLocalRouting extends LocalRoutingNotifier {
  _FakeLocalRouting(this.initial);

  final LocalRoutingIssue? initial;
  int dismissals = 0;

  @override
  LocalRoutingIssue? build() => initial;

  @override
  void dismiss() => dismissals++;
}

class _RecordingToasts extends InAppNotificationController {
  final success = <String>[];

  @override
  ToastificationItem? showSuccessToast(String message) {
    success.add(message);
    return null;
  }
}
