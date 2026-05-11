import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';

/// A frosted-glass container used across the redesigned UI.
///
/// Layer order (bottom → top): backdrop blur → translucent fill → border →
/// child. An optional [glowColor] renders an outer [BoxShadow]; do not stack
/// blurs to fake glow.
///
/// Wrapped in a [RepaintBoundary] so animated children (pulses, value tweens)
/// don't repaint the rest of the screen.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.blur,
    this.opacity,
    this.radius = RaynRadius.card,
    this.glowColor,
    this.padding = const EdgeInsets.all(RaynSpacing.lg),
    this.border,
    this.fillColor,
  });

  final Widget child;

  /// Backdrop blur sigma. When null, falls back to
  /// `context.rayn.glassBlurSigma` (20 dark / 12 light).
  final double? blur;

  /// Tints the active palette's text color and uses that as the fill. When
  /// null AND [fillColor] is null, the palette's `glassFill` is used as-is.
  /// Caller-supplied [fillColor] always wins.
  final double? opacity;
  final double radius;
  final Color? glowColor;
  final EdgeInsetsGeometry padding;
  final Border? border;

  /// Optional explicit fill color. Overrides [opacity] when provided.
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    final double? opacity = this.opacity;
    final Color effectiveFill = fillColor ??
        (opacity != null
            ? palette.textPrimary.withValues(alpha: opacity)
            : palette.glassFill);
    final Border effectiveBorder =
        border ?? Border.all(color: palette.glassBorder);
    final double effectiveBlur = blur ?? palette.glassBlurSigma;

    Widget content = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: Container(
          decoration: BoxDecoration(
            color: effectiveFill,
            borderRadius: borderRadius,
            border: effectiveBorder,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );

    if (glowColor != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(color: glowColor!, blurRadius: 32, spreadRadius: 2),
          ],
        ),
        child: content,
      );
    }

    return RepaintBoundary(child: content);
  }
}
