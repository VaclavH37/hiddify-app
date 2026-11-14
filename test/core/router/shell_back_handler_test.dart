import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_back_handler.dart';

/// The app's shell, cut down to what back handling depends on: the same two
/// branches in the same order, Settings with About as a sub-page opened by
/// `go`, and the shell wrapped in [ShellBackHandler] as `RaynShell` does.
GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => ShellBackHandler(navigationShell: shell, child: Scaffold(body: shell)),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(name: 'home', path: '/home', builder: (_, _) => const Text('home'))],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              name: 'settings',
              path: '/settings',
              builder: (_, _) => const Text('settings'),
              routes: [GoRoute(name: 'about', path: '/about', builder: (_, _) => const Text('about'))],
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  late List<String> exits;

  setUp(() => exits = []);

  Future<GoRouter> pumpShell(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits.add('exit');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('back at Home leaves the app when Settings was never visited', (tester) async {
    await pumpShell(tester);
    await pressBack(tester);
    expect(exits, ['exit']);
  });

  testWidgets('back at Home leaves the app after Settings was left with About open', (tester) async {
    // flutter/flutter#193098: go_router 16 keeps the Settings branch mounted
    // with About on top, and that inactive branch vetoes every back press. Before
    // the shell handled back itself, this press was swallowed and the app could
    // not be closed with back at all.
    final router = await pumpShell(tester);
    router.goNamed('settings');
    await tester.pumpAndSettle();
    router.go(router.namedLocation('about'));
    await tester.pumpAndSettle();
    router.go('/home');
    await tester.pumpAndSettle();

    await pressBack(tester);

    expect(exits, ['exit']);
  });

  testWidgets('back on About closes About and stays in Settings', (tester) async {
    final router = await pumpShell(tester);
    router.goNamed('settings');
    await tester.pumpAndSettle();
    router.go(router.namedLocation('about'));
    await tester.pumpAndSettle();

    await pressBack(tester);

    expect(find.text('settings'), findsOneWidget);
    expect(exits, isEmpty);
  });

  testWidgets('back at the root of Settings goes Home without leaving the app', (tester) async {
    final router = await pumpShell(tester);
    router.goNamed('settings');
    await tester.pumpAndSettle();

    await pressBack(tester);

    expect(find.text('home'), findsOneWidget);
    expect(exits, isEmpty);
  });
}
