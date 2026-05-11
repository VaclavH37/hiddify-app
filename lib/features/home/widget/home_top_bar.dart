import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/gen/assets.gen.dart';

/// Desktop overlay: a single glass-wrapped bell pinned to the top-right of
/// the home canvas. The constellation background shows through the blur.
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
        child: Align(
          alignment: Alignment.topRight,
          child: _NotificationBell(),
        ),
      ),
    );
  }
}

/// Mobile AppBar: hamburger + brand wordmark + bell. Designed to overlay the
/// constellation background, so the host Scaffold should set
/// `extendBodyBehindAppBar: true`.
class HomeMobileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeMobileAppBar({super.key});

  static const double _height = 56;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: RaynSpacing.lg,
      // Hamburger removed on mobile — primary nav lives in the bottom
      // NavigationBar (Home + Settings).
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Assets.images.logo.svg(width: 24, height: 24),
          const SizedBox(width: RaynSpacing.sm),
          Text(
            'Rayn VPN',
            style: RaynTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: RaynSpacing.md),
          child: _NotificationBell(),
        ),
      ],
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: EdgeInsets.zero,
      radius: RaynRadius.button,
      child: Semantics(
        button: true,
        label: 'Notifications',
        child: IconButton(
          icon: Icon(Icons.notifications_none_rounded, color: context.rayn.textPrimary),
          tooltip: 'Notifications',
          onPressed: () {
            // TODO(notifications): wire to inbox (open item §8 — bell is
            // visual-only stub for this PR).
          },
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.button)),
            padding: const EdgeInsets.all(RaynSpacing.sm),
          ),
        ),
      ),
    );
  }
}
