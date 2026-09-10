import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// A purchase screen's waiting state: a small indicator, an optional [label]
/// (loading offers, activating the plan) and an optional [hint] under it
/// (how long it usually takes). Shared by the sign-up paywall and the
/// plan-transition screen, which each used to carry a private copy.
class PurchaseProgress extends StatelessWidget {
  const PurchaseProgress({super.key, this.label, this.hint});

  final String? label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RaynSpacing.xxl),
      child: Column(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          if (label != null) ...[
            const SizedBox(height: RaynSpacing.lg),
            Text(
              label!,
              style: RaynTypography.paragraph.copyWith(color: palette.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: RaynSpacing.xs),
            Text(
              hint!,
              style: RaynTypography.caption.copyWith(color: palette.textMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
