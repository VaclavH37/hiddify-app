import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_colors.dart';

/// Rayn VPN design tokens — typography scale.
///
/// Backed by the Geist font family (declared in `pubspec.yaml`).
class RaynTypography {
  const RaynTypography._();

  static const String _family = 'Geist';

  static const TextStyle display = TextStyle(
    fontFamily: _family,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: RaynColors.textPrimary,
  );

  static const TextStyle title = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: RaynColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: RaynColors.textPrimary,
  );

  static const TextStyle metric = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: RaynColors.textPrimary,
  );

  static const TextStyle metricUnit = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: RaynColors.textSecondary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: RaynColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: RaynColors.textMuted,
  );
}
