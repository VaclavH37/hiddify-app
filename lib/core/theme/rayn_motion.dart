import 'package:flutter/material.dart';

/// Rayn VPN design tokens — motion durations & curves.
///
/// The legacy `kAnimationDuration` (250ms) in `lib/core/model/constants.dart`
/// stays for now; new code should reach for [RaynMotion.standard] instead.
class RaynMotion {
  const RaynMotion._();

  // Durations
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 250);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 600);

  // Curves
  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve ambient = Curves.easeInOut;
  static const Curve emphasis = Cubic(0.2, 0.8, 0.2, 1.0);
}

/// Returns true when the user has requested reduced motion at the OS level.
///
/// Animation controllers should bail (skip `.repeat()`, render the static end
/// state) when this returns true.
bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;
