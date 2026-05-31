import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// Inline page header (large title + optional subtitle) used by Settings,
/// Logs, and About. Replaces the default Material [AppBar] on those pages.
///
/// [leading] is an optional widget rendered to the left of the title (e.g.
/// a back arrow on sub-pages). [trailing] is a list of action widgets
/// rendered as a Row on the right (typically icon buttons + the notification
/// bell). Both align to the top of the title so a multi-line subtitle does
/// not push them down.
class RaynPageHeader extends StatelessWidget {
  const RaynPageHeader({super.key, required this.title, this.subtitle, this.leading, this.trailing = const []});

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.xl, RaynSpacing.xl, RaynSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: RaynSpacing.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: RaynTypography.display.copyWith(color: palette.textPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: RaynSpacing.xs),
                  Text(subtitle!, style: RaynTypography.caption.copyWith(color: palette.textMuted)),
                ],
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: RaynSpacing.md),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < trailing.length; i++) ...[
                  if (i > 0) const SizedBox(width: RaynSpacing.sm),
                  trailing[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
