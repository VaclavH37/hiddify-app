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
    required this.glassBorder,
    required this.shadow,
    required this.success,
    required this.warning,
    required this.danger,
    required this.stateDisconnected,
    required this.stateConnecting,
    required this.stateConnected,
    required this.stateError,
    required this.logoMark,
    required this.orbFill,
    required this.navSelectedFill,
  });

  /// Home page scaffold / canvas behind the map background.
  final Color bgPrimary;

  /// Sidebar (NavigationRail) and mobile NavigationBar surface.
  final Color bgSurface;

  /// Background of Settings, Logs, and About pages (the area to the right of
  /// the sidebar). One step lighter / brighter than [bgSurface] in both
  /// themes so the content area sits visually above the rail.
  final Color pageBackground;

  /// Fill for a surface raised one step above the page or canvas: every
  /// `RaynSurface` (the location card, list rows, the banner) and the payment
  /// flow's plan cards. Depth in this app is tone, not blur or borders, so this
  /// is a real step in both themes: on dark it is about twelve levels above
  /// [pageBackground], which is what a card needs to read as a card without a
  /// hairline; the previous value was four levels up and invisible.
  final Color groupFill;

  /// Default body-text color. Inherited via DefaultTextStyle.
  final Color textPrimary;

  /// Labels, sidebar inactive items, secondary metadata.
  final Color textSecondary;

  /// Captions and helper text.
  final Color textMuted;

  /// Hairline: the border on a light-mode surface, and inset dividers.
  final Color glassBorder;

  /// Card drop shadow.
  final Color shadow;

  /// Semantic status colors.
  final Color success;
  final Color warning;
  final Color danger;

  /// Connection-state brand colours. The connection button tints the logo
  /// silhouette with one of these (BlendMode.srcIn), so they ARE the state
  /// indicator — there is no separate coloured asset per state.
  ///
  /// Deliberately identical in both brightnesses: these are brand colours, not
  /// surface colours, and the mark has to read as "the amber one" regardless of
  /// theme. `stateError` has no ConnectionStatus member — it is reached from an
  /// `AsyncError`.
  final Color stateDisconnected;

  /// The same amber as [stateConnected], restoring the pre-rollout behaviour.
  ///
  /// This looks like a mistake and is not. Connecting is not a colour the user
  /// sees on its own: `Connecting()` is brief, and the core reports
  /// `Connected()` with no URL-test delay yet for most of the wait — a state
  /// the button paints in its own pale yellow-green and still LABELS
  /// "connecting" (see connection_button.dart). So the sequence is
  /// amber → yellow-green → amber, and with the button's 600ms ColorTween
  /// between them that is what reads as a pulse while connecting.
  ///
  /// Giving this its own hue splits that pulse into two unrelated colours.
  /// Two have been tried and reverted: #3A84CA, and #7C3AED.
  ///
  /// The cost is real: connecting and connected are now indistinguishable by
  /// colour alone, on the orb and in the system tray. The label and the tray
  /// tooltip carry the difference instead.
  final Color stateConnecting;
  final Color stateConnected;
  final Color stateError;

  /// The brand mark's own amber — the same value as the app icon and the
  /// splash. Identical on both themes on purpose: the mark IS the brand, not a
  /// surface treatment, so it must not read as white in the app and amber on
  /// the icon the user just tapped.
  ///
  /// Still a palette token rather than a bare constant, because the mark ships
  /// as a flat silhouette tinted at render time — every site has to pass *a*
  /// colour, and one token is what stops them drifting apart.
  final Color logoMark;

  /// The connection orb's disc. White in both themes on purpose: the disc is
  /// the ground the tinted mark sits on, and the mark's colours were chosen
  /// against white. A token rather than a literal for the same reason as
  /// [logoMark] — every site that draws the disc has to pass a colour, and one
  /// token is what stops them drifting apart.
  final Color orbFill;

  /// Sidebar and bottom-bar selected-item fill.
  final Color navSelectedFill;

  static const RaynPalette dark = RaynPalette(
    bgPrimary: Color(0xFF101111),
    bgSurface: Color(0xFF111111),
    pageBackground: Color(0xFF1A1816),
    groupFill: Color(0xFF262320),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    textMuted: Color(0x80FFFFFF),
    glassBorder: Color(0x1FFFFFFF),
    shadow: Color(0x66000000),
    success: Color(0xFF3DD68C),
    warning: Color(0xFFE8C547),
    danger: Color(0xFFE5484D),
    stateDisconnected: Color(0xFF1E3A8A),
    stateConnecting: Color(0xFFF59E0B),
    stateConnected: Color(0xFFF59E0B),
    stateError: Color(0xFFF24444),
    logoMark: Color(0xFFF59E0B),
    orbFill: Color(0xFFFFFFFF),
    navSelectedFill: Color(0x14FFFFFF),
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
    glassBorder: Color(0xFFEFE6D9),
    shadow: Color(0x142B1E12),
    success: Color(0xFF15803D),
    warning: Color(0xFFCA8A04),
    danger: Color(0xFFDC2626),
    stateDisconnected: Color(0xFF1E3A8A),
    stateConnecting: Color(0xFFF59E0B),
    stateConnected: Color(0xFFF59E0B),
    stateError: Color(0xFFF24444),
    logoMark: Color(0xFFF59E0B),
    orbFill: Color(0xFFFFFFFF),
    navSelectedFill: Color(0x1FD6A34A),
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
    Color? glassBorder,
    Color? shadow,
    Color? success,
    Color? warning,
    Color? danger,
    Color? stateDisconnected,
    Color? stateConnecting,
    Color? stateConnected,
    Color? stateError,
    Color? logoMark,
    Color? orbFill,
    Color? navSelectedFill,
  }) {
    return RaynPalette(
      bgPrimary: bgPrimary ?? this.bgPrimary,
      bgSurface: bgSurface ?? this.bgSurface,
      pageBackground: pageBackground ?? this.pageBackground,
      groupFill: groupFill ?? this.groupFill,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      glassBorder: glassBorder ?? this.glassBorder,
      shadow: shadow ?? this.shadow,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      stateDisconnected: stateDisconnected ?? this.stateDisconnected,
      stateConnecting: stateConnecting ?? this.stateConnecting,
      stateConnected: stateConnected ?? this.stateConnected,
      stateError: stateError ?? this.stateError,
      logoMark: logoMark ?? this.logoMark,
      orbFill: orbFill ?? this.orbFill,
      navSelectedFill: navSelectedFill ?? this.navSelectedFill,
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
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      stateDisconnected: Color.lerp(stateDisconnected, other.stateDisconnected, t)!,
      stateConnecting: Color.lerp(stateConnecting, other.stateConnecting, t)!,
      stateConnected: Color.lerp(stateConnected, other.stateConnected, t)!,
      stateError: Color.lerp(stateError, other.stateError, t)!,
      logoMark: Color.lerp(logoMark, other.logoMark, t)!,
      orbFill: Color.lerp(orbFill, other.orbFill, t)!,
      navSelectedFill: Color.lerp(navSelectedFill, other.navSelectedFill, t)!,
    );
  }
}

extension RaynPaletteContext on BuildContext {
  /// Shorthand for the active [RaynPalette] (light or dark) registered on
  /// the inherited [Theme]. Falls back to [RaynPalette.dark] if no extension
  /// is registered, so widgets used in Material previews still render.
  RaynPalette get rayn => Theme.of(this).extension<RaynPalette>() ?? RaynPalette.dark;
}
