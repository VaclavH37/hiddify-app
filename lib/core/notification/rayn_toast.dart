import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/rayn_motion.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';
import 'package:toastification/toastification.dart';

/// What a toast is telling the user. The icon carries it; the surface is the
/// same surface for all three.
enum NotificationType { info, error, success }

/// A toast on the app's own surface: an elevated [RaynSurface], a 22px icon
/// tinted by [type], the message, and a small close button that is always
/// visible because a phone has no hover.
///
/// This replaced the toast library's coloured style, which painted a
/// saturated fill with its own icons and shadows and was the last piece of
/// stock chrome left after the redesign. The library still owns the queue,
/// the timers, the overlay and swipe-to-dismiss; only the widget is ours.
class RaynToast extends StatelessWidget {
  const RaynToast({super.key, required this.type, required this.message, required this.onClose});

  final NotificationType type;
  final String message;
  final VoidCallback onClose;

  static IconData iconFor(NotificationType type) => switch (type) {
    NotificationType.info => Icons.info_outline_rounded,
    NotificationType.success => Icons.check_circle_outline_rounded,
    NotificationType.error => Icons.error_outline_rounded,
  };

  static Color tintFor(NotificationType type, RaynPalette palette) => switch (type) {
    NotificationType.info => palette.accentText,
    NotificationType.success => palette.success,
    NotificationType.error => palette.danger,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Semantics(
      liveRegion: true,
      child: RaynSurface(
        elevated: true,
        radius: RaynRadius.group,
        padding: const EdgeInsets.fromLTRB(RaynSpacing.lg, RaynSpacing.md, RaynSpacing.sm, RaynSpacing.md),
        // Everything centres on the row's vertical middle: the 32px close
        // button sets the height of a one-line toast, and the text and icon
        // sit level with it rather than on its top edge.
        child: Row(
          children: [
            Icon(iconFor(type), size: 22, color: tintFor(type, palette)),
            const SizedBox(width: RaynSpacing.md),
            Expanded(
              child: Text(
                message,
                style: RaynTypography.body.copyWith(color: palette.textPrimary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: RaynSpacing.sm),
            IconButton(
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 18, color: palette.textMuted),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            ),
          ],
        ),
      ),
    );
  }
}

/// The toast's entrance and exit: a fade with a short slide in from the edge
/// it sits on, on the app's standard curve; a fade alone when the OS asks
/// for reduced motion.
Widget raynToastTransition(BuildContext context, Animation<double> animation, Alignment alignment, Widget child) {
  final curved = CurvedAnimation(parent: animation, curve: RaynMotion.standardCurve);
  final fade = FadeTransition(opacity: curved, child: child);
  if (reduceMotion(context)) return fade;
  final slide = Tween<Offset>(begin: Offset(0, alignment.y >= 0 ? 0.15 : -0.15), end: Offset.zero).animate(curved);
  return SlideTransition(position: slide, child: fade);
}

/// The widest a toast gets, and the margin that keeps it inside the shorter
/// side of any screen. The library sizes a toast to its configured width
/// exactly, so a fixed 480 would overflow a phone; the shorter side keeps the
/// width the same in both orientations, which matters because the library
/// keeps the first configuration it sees for an alignment.
double raynToastWidth(BuildContext context) {
  return math.min(480, MediaQuery.sizeOf(context).shortestSide - 2 * RaynSpacing.lg);
}

/// One position rule on every platform: bottom centre, above the bottom
/// navigation bar when the shell shows one (the mobile breakpoint), on the
/// app's standard duration and curve. The library adds the safe area and the
/// keyboard inset itself, so the margin does not.
ToastificationConfig raynToastConfig({required double itemWidth}) {
  return ToastificationConfig(
    alignment: AlignmentDirectional.bottomCenter,
    itemWidth: itemWidth,
    animationDuration: RaynMotion.standard,
    animationBuilder: raynToastTransition,
    marginBuilder: (context, alignment) {
      // Read at show time, not at configuration time, so a desktop window
      // resized across the breakpoint gets the right clearance.
      final aboveBar = Breakpoint(context).isMobile() ? _navigationBarHeight + RaynSpacing.md : RaynSpacing.xl;
      return EdgeInsets.fromLTRB(RaynSpacing.lg, 0, RaynSpacing.lg, aboveBar);
    },
  );
}

/// Material 3's NavigationBar height; the shell does not override it.
const double _navigationBarHeight = 80;
