import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// Small-caps muted section label rendered above a group of
/// [RaynSettingsTile]s (e.g., "ACCOUNT", "GENERAL", "NETWORK").
class RaynSectionHeader extends StatelessWidget {
  const RaynSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.lg, RaynSpacing.xl, RaynSpacing.sm),
      child: Text(
        label.toUpperCase(),
        style: RaynTypography.label.copyWith(color: palette.textMuted, letterSpacing: 1.2, fontWeight: FontWeight.w600),
      ),
    );
  }
}
