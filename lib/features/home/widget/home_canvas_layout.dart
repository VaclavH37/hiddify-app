import 'package:flutter/rendering.dart';
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
  HomeCanvasLayout({required this.topInset, required this.orbDiameter});

  /// Height to keep clear at the top: the app bar on mobile, the band the bell
  /// occupies on desktop. The banner goes immediately below it.
  final double topInset;

  /// Diameter of the orb's circle. The orb child is taller than this because
  /// its label hangs below, and it is the circle that should be centred.
  final double orbDiameter;

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
  }

  @override
  bool shouldRelayout(HomeCanvasLayout oldDelegate) =>
      topInset != oldDelegate.topInset || orbDiameter != oldDelegate.orbDiameter;
}
