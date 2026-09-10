import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';

/// Desktop: the bell alone, pinned to the top-right of the home canvas. The
/// rail carries the brand there.
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

/// Mobile app bar: the wordmark on the left, the bell on the right, over the
/// map (the host Scaffold sets `extendBodyBehindAppBar: true`). Standard
/// toolbar height; the wordmark is at app-bar proportion, since the mark in
/// the orb is the brand on this screen and a second, larger one above it
/// outweighed the status label the user is actually there to read.
class HomeMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeMobileAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: RaynSpacing.lg,
      title: const RaynWordmark(iconSize: 28, wordSize: 20, suffixSize: 12, gap: 6),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: RaynSpacing.sm),
          child: RaynNotificationBell(),
        ),
      ],
    );
  }
}
