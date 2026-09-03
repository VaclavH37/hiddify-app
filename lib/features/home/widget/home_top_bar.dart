import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';

/// Desktop overlay: a single glass-wrapped bell pinned to the top-right of
/// the home canvas. The map background shows through the blur.
///
/// The Auto-connect toggle from the original design was dropped; existing
/// auto-start lives in Settings (§1 of the implementation plan).
class HomeTopBarBell extends StatelessWidget {
  const HomeTopBarBell({super.key});

  @override
  Widget build(BuildContext context) {
    return const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(RaynSpacing.lg),
        child: Align(alignment: Alignment.topRight, child: RaynNotificationBell()),
      ),
    );
  }
}

/// Mobile AppBar: hamburger + brand wordmark + bell. Designed to overlay the
/// map background, so the host Scaffold should set
/// `extendBodyBehindAppBar: true`.
class HomeMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeMobileAppBar({super.key});

  // Raised from the Material default 56 to clear the doubled wordmark: the
  // 48px icon is the tallest element, and at 56 it would sit with 4px of air
  // top and bottom and read as clipped. 72 keeps a deliberate 12px.
  static const double _height = 72;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: RaynSpacing.lg,
      // Hamburger removed on mobile — primary nav lives in the bottom
      // NavigationBar (Home + Settings).
      // Brand wordmark at DOUBLE the WORDMARK.md app-bar proportions, by
      // explicit request — the mark is the only branding on the connection
      // screen, so it carries more weight here than in a dense app bar. All
      // four values are scaled together so the mark doesn't distort.
      title: const RaynWordmark(iconSize: 48, wordSize: 40, suffixSize: 24, gap: 12),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: RaynSpacing.md),
          child: RaynNotificationBell(),
        ),
      ],
    );
  }
}
