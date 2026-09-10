import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/features/auth/widget/auth_layout.dart';

/// Pins the shape every pre-auth screen shares: content capped at 480 and
/// centred, the leading row always reserved, the hero at 80% by default, a
/// footer that stays outside the scroll region, and a body that scrolls only
/// when it has to.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
      home: child,
    );
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('content is capped at 480 and centred on a wide window', (tester) async {
    await resize(tester, const Size(900, 700));
    await tester.pumpWidget(host(const AuthLayout(children: [SizedBox(height: 10)])));

    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    expect(scroll.width, AuthLayout.maxWidth);
    expect(scroll.left, (900 - AuthLayout.maxWidth) / 2);
  });

  testWidgets('the leading row is reserved even with nothing in it', (tester) async {
    await resize(tester, const Size(400, 800));
    await tester.pumpWidget(host(const AuthLayout(children: [])));
    final heroWithoutLeading = tester.getTopLeft(find.byType(RaynWordmarkHero)).dy;

    await tester.pumpWidget(
      host(
        const AuthLayout(
          leading: Icon(Icons.arrow_back, key: Key('back')),
          children: [],
        ),
      ),
    );
    expect(find.byKey(const Key('back')), findsOneWidget);
    expect(tester.getTopLeft(find.byType(RaynWordmarkHero)).dy, heroWithoutLeading);
  });

  testWidgets('the hero keeps its 80% width and the title is centred', (tester) async {
    await resize(tester, const Size(400, 800));
    await tester.pumpWidget(host(const AuthLayout(title: 'Sign in', children: [])));

    expect(tester.widget<RaynWordmarkHero>(find.byType(RaynWordmarkHero)).widthFactor, 0.8);
    expect(tester.widget<Text>(find.text('Sign in')).textAlign, TextAlign.center);
  });

  testWidgets('the footer sits outside the scroll region', (tester) async {
    await resize(tester, const Size(400, 800));
    await tester.pumpWidget(
      host(
        const AuthLayout(
          footer: SizedBox(key: Key('footer'), height: 48),
          children: [SizedBox(height: 10)],
        ),
      ),
    );

    expect(find.byKey(const Key('footer')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(SingleChildScrollView), matching: find.byKey(const Key('footer'))),
      findsNothing,
    );
    final footer = tester.getRect(find.byKey(const Key('footer')));
    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    expect(footer.top, greaterThanOrEqualTo(scroll.bottom));
  });

  testWidgets('a short body does not scroll; a tall one does', (tester) async {
    await resize(tester, const Size(400, 800));
    await tester.pumpWidget(host(const AuthLayout(children: [SizedBox(key: Key('short'), height: 10)])));
    final before = tester.getTopLeft(find.byKey(const Key('short')));
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('short'))), before);

    await tester.pumpWidget(host(const AuthLayout(children: [SizedBox(key: Key('tall'), height: 2000)])));
    final top = tester.getTopLeft(find.byKey(const Key('tall'))).dy;
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('tall'))).dy, lessThan(top));
  });
}
