import 'package:flutter/material.dart';

/// Rayn VPN design tokens: motion.
///
/// Three durations and one curve. Nothing in the app animates while idle;
/// motion marks a change of state and stops. Page transitions are the
/// platform's own, set once in `AppTheme`.
class RaynMotion {
  const RaynMotion._();

  /// A label swap, a switcher.
  static const Duration fast = Duration(milliseconds: 180);

  /// A layout change: the banner appearing, a size settling.
  static const Duration standard = Duration(milliseconds: 250);

  /// A colour or opacity moving to a new state: the orb's tint.
  static const Duration medium = Duration(milliseconds: 320);

  static const Curve standardCurve = Curves.easeOutCubic;
}

/// Returns true when the user has requested reduced motion at the OS level.
///
/// Animation controllers should bail (skip `.repeat()`, render the static end
/// state) when this returns true.
bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;
