import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// Inline page title used by Settings, About, the location picker and the
/// inbox, in place of a Material [AppBar]. Scrolls with the content.
///
/// [leading] is an optional widget rendered to the left of the title (a back
/// arrow on sub-pages). [trailing] is a list of actions rendered as a Row on
/// the right. There is no subtitle slot any more: every page had one and
/// every one restated its title.
class RaynPageHeader extends StatelessWidget {
  const RaynPageHeader({
    super.key,
    required this.title,
    this.leading,
    this.trailing = const [],
    this.padding = const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.xl, RaynSpacing.xl, RaynSpacing.lg),
  });

  final String title;
  final Widget? leading;
  final List<Widget> trailing;

  /// Pages whose scroll view already carries the horizontal margin pass a
  /// vertical-only padding here.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: RaynSpacing.sm)],
          Expanded(
            child: Text(title, style: RaynTypography.display.copyWith(color: palette.textPrimary)),
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
