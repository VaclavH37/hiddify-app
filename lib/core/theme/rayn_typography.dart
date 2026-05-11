import 'package:flutter/material.dart';

/// Rayn VPN design tokens — typography scale.
///
/// Backed by the Geist font family (declared in `pubspec.yaml`). Styles are
/// intentionally **uncolored** — body color is inherited via
/// [DefaultTextStyle] (driven by `context.rayn.textPrimary` at the home
/// scaffold root), and role-specific colors (label, caption, metricUnit)
/// are applied at the call site via `.copyWith(color: context.rayn.textSecondary)`
/// or `context.rayn.textMuted`.
class RaynTypography {
  const RaynTypography._();

  static const String _family = 'Geist';

  static const TextStyle display = TextStyle(
    fontFamily: _family,
    fontSize: 32,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle metric = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle metricUnit = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    fontWeight: FontWeight.w400,
  );
}
