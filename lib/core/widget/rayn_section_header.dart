import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// Label above a [RaynSettingsGroup]: sentence case, secondary colour, inset
/// to the group's content edge so it lines up with the rows' icons.
///
/// It used to be uppercased with wide tracking. Tracked small caps are the
/// stock "premium" move of generated interfaces; every settings screen people
/// actually use (the OS's own included) labels its groups in sentence case.
class RaynSectionHeader extends StatelessWidget {
  const RaynSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(RaynSpacing.lg, RaynSpacing.xl, RaynSpacing.lg, RaynSpacing.sm),
      child: Text(label, style: RaynTypography.label.copyWith(color: palette.textSecondary)),
    );
  }
}
