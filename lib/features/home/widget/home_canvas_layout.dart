import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';

/// The pieces of the connection page, laid out by [HomeCanvasLayout].
enum HomeCanvasSlot { banner, orb, card }

/// Places the connection page's three pieces without any of them knowing
/// about the others.
///
/// The orb is the anchor: its circle sits at the vertical centre of the canvas,
/// which is where the page has always put it. Below it, in flow, comes the
/// location card after a fixed gap. The banner, when there is one, sits at the
/// top just under [topInset].
///
/// This replaces a `Stack` of `Transform.translate` offsets that had been
/// worked out by hand from the children's heights. A translate moves paint and
/// hit-testing but takes no part in layout, so nothing stopped the card from
/// sliding under the navigation bar on a short screen, and the banner's
/// position was a separate guess that drifted from the app bar it was meant to
/// clear. Here every child is measured, the group moves up only as far as it
/// must to keep the card inside the canvas, and it never rises into the banner
/// or the app bar.
class HomeCanvasLayout extends MultiChildLayoutDelegate {
  HomeCanvasLayout({required this.topInset, required this.orbDiameter, this.onNeededHeight});

  /// Height to keep clear at the top: the app bar on mobile, the band the bell
  /// occupies on desktop. The banner goes immediately below it.
  final double topInset;

  /// Diameter of the orb's circle. The orb child is taller than this because
  /// its label hangs below, and it is the circle that should be centred.
  final double orbDiameter;

  /// Told, on every layout, the height the canvas needs to fit everything:
  /// the top inset, the banner if there is one, the orb, the card and the
  /// space below it. Called during layout, so a listener must not rebuild
  /// synchronously ([HomeCanvas] waits for the end of the frame).
  final ValueChanged<double>? onNeededHeight;

  /// Gap between [topInset] and the banner.
  static const double bannerGap = RaynSpacing.sm;

  /// Gap between the banner and the orb when the two would otherwise meet.
  static const double bannerToOrb = RaynSpacing.lg;

  /// Gap between the orb's label and the location card.
  static const double orbToCard = RaynSpacing.xxl;

  /// Space kept below the card.
  static const double bottomInset = RaynSpacing.lg;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(size);

    var bannerHeight = 0.0;
    if (hasChild(HomeCanvasSlot.banner)) {
      final bannerSize = layoutChild(HomeCanvasSlot.banner, loose);
      bannerHeight = bannerSize.height;
      positionChild(HomeCanvasSlot.banner, Offset((size.width - bannerSize.width) / 2, topInset + bannerGap));
    }

    final orbSize = layoutChild(HomeCanvasSlot.orb, loose);
    final cardSize = layoutChild(HomeCanvasSlot.card, BoxConstraints.tightFor(width: size.width));

    // Everything from the top of the orb to the bottom of the card, plus the
    // space kept below the card.
    final groupHeight = orbSize.height + orbToCard + cardSize.height + bottomInset;

    // Centre the circle; then move the whole group up if the card would run
    // off the bottom, but never above the banner (or the app bar). When both
    // constraints bind at once the top wins and the card overflows, which the
    // canvas handles by growing and scrolling.
    var orbTop = (size.height - orbDiameter) / 2;
    final overflow = orbTop + groupHeight - size.height;
    if (overflow > 0) orbTop -= overflow;
    final minTop = bannerHeight > 0 ? topInset + bannerGap + bannerHeight + bannerToOrb : topInset;
    if (orbTop < minTop) orbTop = minTop;

    positionChild(HomeCanvasSlot.orb, Offset((size.width - orbSize.width) / 2, orbTop));
    positionChild(HomeCanvasSlot.card, Offset(0, orbTop + orbSize.height + orbToCard));

    onNeededHeight?.call(minTop + groupHeight);
  }

  @override
  bool shouldRelayout(HomeCanvasLayout oldDelegate) =>
      topInset != oldDelegate.topInset || orbDiameter != oldDelegate.orbDiameter;
}

/// The connection page's canvas: [HomeCanvasLayout] in a box that fills the
/// space it is given, and grows and scrolls when the pieces need more.
///
/// The height the pieces need is known only once they have been laid out, so
/// the canvas takes it on the next frame. Until the first layout it uses
/// [minHeight] below [topInset]. Without this the canvas had a fixed minimum
/// that left out the banner: on a short screen with a banner up, the card was
/// pushed past the end of the scroll and could not be reached.
class HomeCanvas extends StatefulWidget {
  const HomeCanvas({
    super.key,
    required this.topInset,
    required this.orbDiameter,
    required this.minHeight,
    required this.banner,
    required this.orb,
    required this.card,
    this.horizontalPadding = 0,
  });

  final double topInset;
  final double orbDiameter;
  final double minHeight;
  final Widget banner;
  final Widget orb;
  final Widget card;
  final double horizontalPadding;

  @override
  State<HomeCanvas> createState() => _HomeCanvasState();
}

class _HomeCanvasState extends State<HomeCanvas> {
  /// What the pieces needed at the last layout; null before the first.
  double? _needed;

  /// A newer value waiting for the end of the frame.
  double? _pending;

  void _onNeededHeight(double needed) {
    final current = _needed;
    if (current != null && (needed - current).abs() < 0.5) {
      _pending = null;
      return;
    }
    final alreadyScheduled = _pending != null;
    _pending = needed;
    if (alreadyScheduled) return;
    // Reported during layout, where a rebuild is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final value = _pending;
      _pending = null;
      if (value == null || !mounted) return;
      setState(() => _needed = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final needed = _needed ?? widget.topInset + widget.minHeight;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            height: math.max(constraints.maxHeight, needed),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
              child: CustomMultiChildLayout(
                delegate: HomeCanvasLayout(
                  topInset: widget.topInset,
                  orbDiameter: widget.orbDiameter,
                  onNeededHeight: _onNeededHeight,
                ),
                children: [
                  LayoutId(id: HomeCanvasSlot.banner, child: widget.banner),
                  LayoutId(id: HomeCanvasSlot.orb, child: widget.orb),
                  LayoutId(id: HomeCanvasSlot.card, child: widget.card),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
