import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';

/// How much a notice should worry the reader. The icon carries it; the
/// surface stays the surface (no tinted fill, no tinted edge), the same rule
/// the notification banner and inbox follow.
enum RaynNoticeTone { info, warning, danger }

/// An inline notice on a [RaynSurface]: an icon tinted by [tone], a paragraph,
/// and optional [actions] (text buttons) beneath it.
///
/// Replaces the payment flow's hand-rolled banners, the expired-plan notice,
/// the plan-transition explainer and the unreachable-host help, each of which
/// drew its own container. A danger notice is a live region, so a screen
/// reader announces an error that appears after a submit.
class RaynNotice extends StatelessWidget {
  const RaynNotice({
    super.key,
    required this.message,
    this.tone = RaynNoticeTone.info,
    this.icon,
    this.actions = const [],
  });

  final String message;
  final RaynNoticeTone tone;

  /// Overrides the tone's default glyph (a schedule or an hourglass, say).
  final IconData? icon;

  final List<Widget> actions;

  /// The icon colour for a tone. Mirrors `notificationTint`.
  static Color tint(RaynNoticeTone tone, RaynPalette palette) => switch (tone) {
    RaynNoticeTone.info => palette.accentText,
    RaynNoticeTone.warning => palette.warning,
    RaynNoticeTone.danger => palette.danger,
  };

  static IconData _defaultIcon(RaynNoticeTone tone) => switch (tone) {
    RaynNoticeTone.info => Icons.info_outline_rounded,
    RaynNoticeTone.warning => Icons.warning_amber_rounded,
    RaynNoticeTone.danger => Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Semantics(
      liveRegion: tone == RaynNoticeTone.danger,
      child: RaynSurface(
        radius: RaynRadius.group,
        padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Optically centres a 20px glyph on the first line of 14px text.
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon ?? _defaultIcon(tone), size: 20, color: tint(tone, palette)),
            ),
            const SizedBox(width: RaynSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, style: RaynTypography.paragraph.copyWith(color: palette.textPrimary)),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: RaynSpacing.sm),
                    Wrap(spacing: RaynSpacing.sm, runSpacing: RaynSpacing.xs, children: actions),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
