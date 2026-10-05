import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_update/app_update_checker.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/app_update/widget/app_update_dialog.dart';
import 'package:hiddify/core/app_update/widget/app_update_tile.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

/// The update dialog and the About row of the Windows EXE build. Nothing is
/// downloaded without the user's Install, Install needs the tunnel, and an
/// important release cannot be skipped.
void main() {
  final t = AppLocale.en.buildSync();

  UpdateManifest offer({bool important = false}) => UpdateManifest(
    schema: kUpdateManifestSchema,
    platform: 'windows',
    channel: 'stable',
    version: '1.6.2',
    build: 10602,
    publishedAt: DateTime.utc(2026, 10, 20, 9),
    important: important,
    installer: UpdateInstaller(path: 'app/windows/RaynVPN-1.6.2-10602-windows.exe', size: 32883242, sha256: 'a' * 64),
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    ConnectionStatus status = const ConnectionStatus.connected(),
    List<Override> overrides = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        translationsProvider.overrideWith((ref) => t),
        connectionNotifierProvider.overrideWith(() => _FixedConnection(status)),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    await container.read(translationsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('AppUpdateDialog', () {
    /// Opens the dialog; [onResult] gets the choice it closes with.
    Future<void> open(
      WidgetTester tester,
      UpdateManifest offer, {
      ConnectionStatus status = const ConnectionStatus.connected(),
      void Function(AppUpdateChoice?)? onResult,
    }) async {
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final choice = await showDialog<AppUpdateChoice>(
                context: context,
                builder: (_) => AppUpdateDialog(offer: offer),
              );
              onResult?.call(choice);
            },
            child: const Text('open'),
          ),
        ),
        status: status,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the version and size, says what installing does, and offers three choices', (tester) async {
      await open(tester, offer());

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Rayn VPN 1.6.2 is ready to install (31 MB).'), findsOneWidget);
      expect(
        find.text('Installing closes Rayn VPN for about half a minute, then opens it again and reconnects.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Skip this version'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Later'), findsOneWidget);
      final install = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Install'));
      expect(install.onPressed, isNotNull);
      expect(install.autofocus, isFalse, reason: 'Enter must not start a download');
    });

    for (final (label, choice) in [
      ('Install', AppUpdateChoice.install),
      ('Later', AppUpdateChoice.later),
      ('Skip this version', AppUpdateChoice.skip),
    ]) {
      testWidgets('"$label" closes the dialog with $choice', (tester) async {
        AppUpdateChoice? result;
        await open(tester, offer(), onResult: (value) => result = value);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(result, choice);
        expect(find.byType(AppUpdateDialog), findsNothing);
      });
    }

    testWidgets('without a connection Install is off and the dialog says why', (tester) async {
      await open(tester, offer(), status: const ConnectionStatus.disconnected());

      expect(find.text('Connect to download it.'), findsOneWidget);
      expect(find.textContaining('reconnects'), findsNothing);
      final install = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Install'));
      expect(install.onPressed, isNull);
    });

    testWidgets('an important release says so and cannot be skipped', (tester) async {
      await open(tester, offer(important: true));

      expect(find.text('This is an important update. Please install it soon.'), findsOneWidget);
      expect(find.text('Skip this version'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Later'), findsOneWidget);
    });
  });

  group('AppUpdateTile', () {
    testWidgets('a waiting release reads "Update to …" and opens the dialog', (tester) async {
      final checker = _FakeChecker(AppUpdateStatus(offer: offer()));
      await pump(tester, const AppUpdateTile(), overrides: [appUpdateCheckerProvider.overrideWith(() => checker)]);

      expect(find.text('Update to 1.6.2'), findsOneWidget);
      await tester.tap(find.text('Update to 1.6.2'));
      expect(checker.shown, 1);
    });

    testWidgets('connected with nothing waiting, it checks now and reports "up to date"', (tester) async {
      final checker = _FakeChecker(const AppUpdateStatus());
      final toasts = _RecordingToasts();
      await pump(
        tester,
        const AppUpdateTile(),
        overrides: [
          appUpdateCheckerProvider.overrideWith(() => checker),
          inAppNotificationControllerProvider.overrideWithValue(toasts),
        ],
      );

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(checker.checks, 1);
      expect(toasts.success, ['Rayn VPN is up to date.']);
    });

    testWidgets('a check that fails says so', (tester) async {
      final toasts = _RecordingToasts();
      await pump(
        tester,
        const AppUpdateTile(),
        overrides: [
          appUpdateCheckerProvider.overrideWith(
            () => _FakeChecker(const AppUpdateStatus(), outcome: AppUpdateOutcome.failed),
          ),
          inAppNotificationControllerProvider.overrideWithValue(toasts),
        ],
      );

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(toasts.errors, ["Couldn't check for updates. Try again later."]);
    });

    testWidgets('while a check runs the row says so and does not start another', (tester) async {
      final checker = _FakeChecker(const AppUpdateStatus(checking: true));
      await pump(tester, const AppUpdateTile(), overrides: [appUpdateCheckerProvider.overrideWith(() => checker)]);

      expect(find.text('Checking…'), findsOneWidget);
      await tester.tap(find.text('Check for updates'));
      expect(checker.checks, 0);
    });

    testWidgets('without a connection it points to the account page instead', (tester) async {
      await pump(
        tester,
        const AppUpdateTile(),
        status: const ConnectionStatus.disconnected(),
        overrides: [appUpdateCheckerProvider.overrideWith(() => _FakeChecker(const AppUpdateStatus()))],
      );

      expect(find.text('Get the latest version'), findsOneWidget);
      expect(find.text('From your account page'), findsOneWidget);
      expect(find.text('Check for updates'), findsNothing);
      expect(find.byIcon(Icons.open_in_new_rounded), findsOneWidget);
    });
  });
}

class _FixedConnection extends ConnectionNotifier {
  _FixedConnection(this.status);

  final ConnectionStatus status;

  @override
  Stream<ConnectionStatus> build() => Stream.value(status);
}

class _FakeChecker extends AppUpdateChecker {
  _FakeChecker(this.initial, {this.outcome = AppUpdateOutcome.upToDate});

  final AppUpdateStatus initial;
  final AppUpdateOutcome outcome;
  int checks = 0;
  int shown = 0;

  @override
  AppUpdateStatus build() => initial;

  @override
  Future<AppUpdateOutcome> checkNow() async {
    checks++;
    return outcome;
  }

  @override
  Future<void> showOffer() async => shown++;
}

class _RecordingToasts extends InAppNotificationController {
  final success = <String>[];
  final errors = <String>[];

  @override
  ToastificationItem? showSuccessToast(String message) {
    success.add(message);
    return null;
  }

  @override
  ToastificationItem? showErrorToast(String message) {
    errors.add(message);
    return null;
  }
}
