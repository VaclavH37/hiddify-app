import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';

/// An opaque card one tone above the page: the location card on the map, list
/// rows, the banner, the About hero.
///
/// This replaced a frosted-glass container (backdrop blur under a translucent
/// fill under a hairline border). Glass only ever made sense over the map, cost
/// a blur layer per card on every surface, and with the hairline was the first
/// thing that made the app look generated rather than designed. Depth comes
/// from tone now: [RaynPalette.groupFill] sits one step above every page and
/// canvas colour in both themes. Light mode keeps a hairline, because cream on
/// cream has no tone to spare; dark mode has none.
///
/// [elevated] adds one soft shadow from the palette's shadow token, for the
/// few surfaces that float over the canvas rather than sit in a list. It is
/// neutral in both themes; nothing here glows.
///
/// Wrapped in a [RepaintBoundary] so animated children (the latency readout,
/// a progress bar) don't repaint the rest of the screen.
class RaynSurface extends StatelessWidget {
  const RaynSurface({
    super.key,
    required this.child,
    this.radius = RaynRadius.card,
    this.padding = const EdgeInsets.all(RaynSpacing.lg),
    this.fillColor,
    this.border,
    this.elevated = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// Overrides the fill; the palette's `groupFill` otherwise.
  final Color? fillColor;

  /// Overrides the border. Light mode's hairline otherwise; nothing in dark.
  final Border? border;

  /// One soft drop shadow, for a surface floating over the canvas.
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final borderRadius = BorderRadius.circular(radius);

    return RepaintBoundary(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fillColor ?? palette.groupFill,
          borderRadius: borderRadius,
          border: border ?? (isLight ? Border.all(color: palette.glassBorder) : null),
          boxShadow: elevated ? [BoxShadow(color: palette.shadow, blurRadius: 20, offset: const Offset(0, 6))] : null,
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}
