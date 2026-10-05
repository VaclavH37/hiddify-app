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
    /// Opens the dialog over a checker in [status]; [onResult] gets the choice
    /// it closes with. Pumps rather than settles: the indeterminate bar of the
    /// later phases never stops moving.
    Future<_FakeChecker> open(
      WidgetTester tester,
      UpdateManifest offer, {
      ConnectionStatus status = const ConnectionStatus.connected(),
      UpdateProgress? progress,
      void Function(AppUpdateChoice?)? onResult,
    }) async {
      final checker = _FakeChecker(AppUpdateStatus(offer: offer, progress: progress));
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
        overrides: [appUpdateCheckerProvider.overrideWith(() => checker)],
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return checker;
    }

    Finder inDialog(Finder matching) => find.descendant(of: find.byType(AppUpdateDialog), matching: matching);

    bool canPop(WidgetTester tester) =>
        tester.widget<PopScope>(inDialog(find.byWidgetPredicate((widget) => widget is PopScope))).canPop;

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
      expect(canPop(tester), isTrue, reason: 'Escape is "Later" while nothing runs');
    });

    testWidgets('Install starts the install for this offer and the dialog stays to show it', (tester) async {
      final checker = await open(tester, offer());
      await tester.tap(find.text('Install'));
      await tester.pump();

      expect(checker.installs.single.build, 10602);
      expect(find.byType(AppUpdateDialog), findsOneWidget);
    });

    for (final (label, choice) in [('Later', AppUpdateChoice.later), ('Skip this version', AppUpdateChoice.skip)]) {
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

    testWidgets('while downloading it shows how far, offers only Cancel, and cannot be dismissed', (tester) async {
      final checker = await open(tester, offer(), progress: const UpdateDownloading(12 * 1024 * 1024, 32883242));

      expect(find.text('Downloading 12 of 31 MB…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(bar.value, closeTo(12 * 1024 * 1024 / 32883242, 1e-9));
      expect(find.text('Install'), findsNothing);
      expect(find.text('Later'), findsNothing);
      expect(canPop(tester), isFalse);

      await tester.tap(find.text('Cancel'));
      expect(checker.cancels, 1);
    });

    for (final (progress, label) in [
      (const UpdateVerifying(), 'Checking the download…'),
      (const UpdateInstalling(), 'Installing. Rayn VPN closes now and opens again in about half a minute.'),
    ]) {
      testWidgets('"$label" has no buttons and cannot be dismissed', (tester) async {
        await open(tester, offer(), progress: progress);

        expect(find.text(label), findsOneWidget);
        expect(inDialog(find.byType(TextButton)), findsNothing);
        expect(inDialog(find.byType(FilledButton)), findsNothing);
        expect(canPop(tester), isFalse);
      });
    }

    for (final (reason, message) in [
      (UpdateFailure.download, "The download didn't finish. Try again later."),
      (UpdateFailure.damaged, 'The download was damaged and has been deleted. Try again later.'),
    ]) {
      testWidgets('a failed $reason says so and closes', (tester) async {
        AppUpdateChoice? result;
        await open(tester, offer(), progress: UpdateFailed(reason), onResult: (value) => result = value);

        expect(find.text(message), findsOneWidget);
        expect(find.text('Open account page'), findsNothing);
        expect(canPop(tester), isTrue);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(result, AppUpdateChoice.later, reason: 'closing a failure never skips the release');
      });
    }

    testWidgets('an installer that would not start points to the account page', (tester) async {
      await open(tester, offer(), progress: const UpdateFailed(UpdateFailure.launch));

      expect(
        find.text("The installer couldn't start. You can get the latest version from your account page."),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Open account page'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Close'), findsOneWidget);
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
  int cancels = 0;
  final installs = <UpdateManifest>[];

  @override
  AppUpdateStatus build() => initial;

  @override
  Future<AppUpdateOutcome> checkNow() async {
    checks++;
    return outcome;
  }

  @override
  Future<void> showOffer() async => shown++;

  @override
  Future<void> install(UpdateManifest offer) async => installs.add(offer);

  @override
  void cancelDownload() => cancels++;
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
