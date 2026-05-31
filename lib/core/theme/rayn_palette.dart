import 'dart:ui';

import 'package:flutter/material.dart';

/// Brightness-aware Rayn design tokens, distributed via [ThemeExtension] so
/// widgets can read `context.rayn.bgPrimary` (etc.) without inspecting
/// `Theme.of(context).brightness` themselves.
///
/// `RaynColors` constants are retained for callers that always render dark
/// (legacy surfaces); new redesign code should reach for the palette.
@immutable
class RaynPalette extends ThemeExtension<RaynPalette> {
  const RaynPalette({
    required this.bgPrimary,
    required this.bgSurface,
    required this.pageBackground,
    required this.groupFill,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.glassFill,
    required this.glassBorder,
    required this.glassBlurSigma,
    required this.shadow,
    required this.success,
    required this.warning,
    required this.danger,
    required this.goldGlow,
    required this.navSelectedFill,
    required this.navSelectedBorder,
  });

  /// Home page scaffold / canvas behind the constellation.
  final Color bgPrimary;

  /// Sidebar (NavigationRail) and mobile NavigationBar surface.
  final Color bgSurface;

  /// Background of Settings, Logs, and About pages (the area to the right of
  /// the sidebar). One step lighter / brighter than [bgSurface] in both
  /// themes so the content area sits visually above the rail.
  final Color pageBackground;

  /// Fill color of [RaynPreferenceGroup] — the bordered container that
  /// wraps a column of rows on settings sub-pages. One step further from
  /// the page background.
  final Color groupFill;

  /// Default body-text color. Inherited via DefaultTextStyle.
  final Color textPrimary;

  /// Labels, sidebar inactive items, secondary metadata.
  final Color textSecondary;

  /// Captions and helper text.
  final Color textMuted;

  /// Default GlassSurface fill (translucent on dark; mostly opaque on light).
  final Color glassFill;

  /// Default GlassSurface border.
  final Color glassBorder;

  /// Default GlassSurface BackdropFilter blur sigma.
  final double glassBlurSigma;

  /// Card drop shadow.
  final Color shadow;

  /// Semantic status colors.
  final Color success;
  final Color warning;
  final Color danger;

  /// Pre-mixed gold glow (alpha already baked in) used by the ping-pill /
  /// orb shadow.
  final Color goldGlow;

  /// Sidebar active-item pill background and border.
  final Color navSelectedFill;
  final Color navSelectedBorder;

  static const RaynPalette dark = RaynPalette(
    bgPrimary: Color(0xFF101111),
    bgSurface: Color(0xFF111111),
    pageBackground: Color(0xFF1A1816),
    groupFill: Color(0xFF1E1B15),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    textMuted: Color(0x80FFFFFF),
    glassFill: Color(0x14FFFFFF),
    glassBorder: Color(0x1FFFFFFF),
    glassBlurSigma: 20,
    shadow: Color(0x66000000),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFE8C547),
    danger: Color(0xFFE5484D),
    // Alpha encodes the *max* halo intensity; animation breathes from
    // glowMax * 0.6 → glowMax.
    goldGlow: Color(0x80E8A317),
    navSelectedFill: Color(0x14FFFFFF),
    navSelectedBorder: Color(0x1FFFFFFF),
  );

  static const RaynPalette light = RaynPalette(
    bgPrimary: Color(0xFFFCF6EF),
    bgSurface: Color(0xFFF2ECE3),
    // Sidebar (#F2ECE3) → page (#FAF4EB) → group (#FFFCF6): each surface
    // is one step lighter / warmer as the user "descends" into the UI,
    // mirroring the dark-theme hierarchy.
    pageBackground: Color(0xFFFAF4EB),
    groupFill: Color(0xFFFFFCF6),
    textPrimary: Color(0xFF2A241F),
    textSecondary: Color(0xFF6D5A4F),
    textMuted: Color(0xFF8C7A6E),
    glassFill: Color(0xD9FFF9F2),
    glassBorder: Color(0xFFEFE6D9),
    glassBlurSigma: 12,
    shadow: Color(0x142B1E12),
    success: Color(0xFF15803D),
    warning: Color(0xFFCA8A04),
    danger: Color(0xFFDC2626),
    goldGlow: Color(0x33D6A34A),
    navSelectedFill: Color(0x1FD6A34A),
    navSelectedBorder: Color(0x3DD6A34A),
  );

  @override
  RaynPalette copyWith({
    Color? bgPrimary,
    Color? bgSurface,
    Color? pageBackground,
    Color? groupFill,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? glassFill,
    Color? glassBorder,
    double? glassBlurSigma,
    Color? shadow,
    Color? success,
    Color? warning,
    Color? danger,
    Color? goldGlow,
    Color? navSelectedFill,
    Color? navSelectedBorder,
  }) {
    return RaynPalette(
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSurface: bgSurface ?? this.bgSurface,
      pageBackground: pageBackground ?? this.pageBackground,
      groupFill: groupFill ?? this.groupFill,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
      glassBlurSigma: glassBlurSigma ?? this.glassBlurSigma,
      shadow: shadow ?? this.shadow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      goldGlow: goldGlow ?? this.goldGlow,
      navSelectedFill: navSelectedFill ?? this.navSelectedFill,
      navSelectedBorder: navSelectedBorder ?? this.navSelectedBorder,
    );
  }

  @override
  RaynPalette lerp(ThemeExtension<RaynPalette>? other, double t) {
    if (other is! RaynPalette) return this;
    return RaynPalette(
      bgPrimary: Color.lerp(bgPrimary, other.bgPrimary, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      groupFill: Color.lerp(groupFill, other.groupFill, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      glassBlurSigma: lerpDouble(glassBlurSigma, other.glassBlurSigma, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      goldGlow: Color.lerp(goldGlow, other.goldGlow, t)!,
      navSelectedFill: Color.lerp(navSelectedFill, other.navSelectedFill, t)!,
      navSelectedBorder: Color.lerp(navSelectedBorder, other.navSelectedBorder, t)!,
    );
  }
}

extension RaynPaletteContext on BuildContext {
  /// Shorthand for the active [RaynPalette] (light or dark) registered on
  /// the inherited [Theme]. Falls back to [RaynPalette.dark] if no extension
  /// is registered, so widgets used in Material previews still render.
  RaynPalette get rayn => Theme.of(this).extension<RaynPalette>() ?? RaynPalette.dark;
}
