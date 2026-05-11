import 'package:flutter/material.dart';

/// Rayn VPN design tokens — colors.
///
/// LEGACY: prefer `context.rayn.<token>` from `rayn_palette.dart`. These
/// constants only encode the dark-mode palette; light-mode equivalents live
/// on [RaynPalette]. Retained because some always-dark or theme-agnostic
/// surfaces (semantic gold/success/danger that read the same on both modes,
/// `goldPrimary` for active sidebar items) reach for them directly.
class RaynColors {
  const RaynColors._();

  // Background
  static const Color bgPrimary = Color(0xFF101111);
  static const Color bgSecondary = Color(0xFF14131A);

  // Brand gold
  static const Color goldPrimary = Color(0xFFE8A317);
  static const Color goldSoft = Color(0xFFF2C46B);
  static const Color goldGlow = Color(0x55E8A317);

  // Semantic
  static const Color success = Color(0xFF3DD68C);
  static const Color warning = Color(0xFFE8C547);
  static const Color danger = Color(0xFFE5484D);

  // Text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textMuted = Color(0x80FFFFFF);

  // Glass
  static const Color glass = Color(0x14FFFFFF);
  static const Color glassBorder = Color(0x1FFFFFFF);
}
