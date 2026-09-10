import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/home/widget/home_canvas_layout.dart';

/// Pure layout tests for the connection page's canvas. The children are plain
/// boxes of known size, so these pin the geometry the delegate promises without
/// pumping the real widgets (which need the whole provider graph).
void main() {
  const orbDiameter = 148.0;
  const labelBlock = 16.0 + 28.0; // gap + one line of label under the circle
  const orbHeight = orbDiameter + labelBlock;
  const cardHeight = 88.0;

  // The default test surface is 800x600, which would silently clamp a taller
  // canvas, so the surface is sized to the canvas under test.
  Future<void> pumpCanvas(
    WidgetTester tester, {
    required Size size,
    double topInset = 0,
    double bannerHeight = 0,
  }) async {
    await tester.binding.setSurfaceSize(Size(size.width + 40, size.height + 40));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox.fromSize(
            size: size,
            child: CustomMultiChildLayout(
              key: const Key('canvas'),
              delegate: HomeCanvasLayout(topInset: topInset, orbDiameter: orbDiameter),
              children: [
                LayoutId(
                  id: HomeCanvasSlot.banner,
                  child: SizedBox(key: const Key('banner'), width: 300, height: bannerHeight),
                ),
                LayoutId(
                  id: HomeCanvasSlot.orb,
                  child: const SizedBox(key: Key('orb'), width: orbDiameter, height: orbHeight),
                ),
                LayoutId(
                  id: HomeCanvasSlot.card,
                  child: const SizedBox(key: Key('card'), height: cardHeight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Rect rectOf(WidgetTester tester, String key) {
    final origin = tester.getTopLeft(find.byKey(const Key('canvas')));
    return tester.getRect(find.byKey(Key(key))).shift(-origin);
  }

  testWidgets('a tall canvas centres the circle and puts the card below it', (tester) async {
    const size = Size(400, 700);
    await pumpCanvas(tester, size: size);

    final orb = rectOf(tester, 'orb');
    expect(orb.top, (size.height - orbDiameter) / 2);
    expect(orb.center.dx, size.width / 2);

    final card = rectOf(tester, 'card');
    expect(card.top, orb.bottom + HomeCanvasLayout.orbToCard);
    expect(card.left, 0);
    expect(card.width, size.width);
    expect(card.bottom, lessThanOrEqualTo(size.height - HomeCanvasLayout.bottomInset));
  });

  testWidgets('a short canvas lifts the group so the card stays inside', (tester) async {
    // 368x568 is the desktop minimum window; the body is shorter still once
    // the app bar and navigation bar take their share.
    const size = Size(368, 400);
    await pumpCanvas(tester, size: size);

    final orb = rectOf(tester, 'orb');
    final card = rectOf(tester, 'card');
    expect(card.bottom, size.height - HomeCanvasLayout.bottomInset);
    expect(orb.top, lessThan((size.height - orbDiameter) / 2));
    expect(orb.top, greaterThanOrEqualTo(0));
  });

  testWidgets('the group never rises into the top inset', (tester) async {
    const size = Size(368, 300);
    const topInset = 100.0;
    await pumpCanvas(tester, size: size, topInset: topInset);

    // Too short for everything: the top wins and the card overflows, which is
    // what the scrolling canvas is for.
    expect(rectOf(tester, 'orb').top, topInset);
  });

  testWidgets('a banner sits under the top inset and leaves a centred circle alone when there is room', (tester) async {
    const size = Size(400, 760);
    const topInset = 100.0;
    const bannerHeight = 80.0;
    await pumpCanvas(tester, size: size, topInset: topInset, bannerHeight: bannerHeight);

    final banner = rectOf(tester, 'banner');
    expect(banner.top, topInset + HomeCanvasLayout.bannerGap);
    expect(banner.center.dx, size.width / 2);

    final orb = rectOf(tester, 'orb');
    expect(orb.top, (size.height - orbDiameter) / 2);
    expect(orb.top, greaterThanOrEqualTo(banner.bottom + HomeCanvasLayout.bannerToOrb));
  });

  testWidgets('a banner on a short canvas keeps the orb below it', (tester) async {
    const size = Size(400, 480);
    const topInset = 100.0;
    const bannerHeight = 80.0;
    await pumpCanvas(tester, size: size, topInset: topInset, bannerHeight: bannerHeight);

    final banner = rectOf(tester, 'banner');
    final orb = rectOf(tester, 'orb');
    expect(orb.top, banner.bottom + HomeCanvasLayout.bannerToOrb);
    expect(orb.top, greaterThan((size.height - orbDiameter) / 2));
  });
}
