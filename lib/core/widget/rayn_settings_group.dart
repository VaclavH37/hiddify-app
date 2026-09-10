import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/equal_height_column.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';

/// A grouped list: one opaque surface holding a stack of rows, with an inset
/// hairline between neighbours. The same shape on every settings screen, so
/// the sections read as one system rather than as a page assembled from
/// three different tile-stacking habits (which is what it was).
///
/// Every row in a group is as tall as the group's tallest row, so a row with
/// a subtitle next to one without does not leave the list looking ragged.
class RaynSettingsGroup extends StatelessWidget {
  const RaynSettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return RaynSurface(
      radius: RaynRadius.group,
      padding: EdgeInsets.zero,
      // The separator is inset to the rows' content edge, not the surface
      // edge: a full-bleed line would cut the group into separate cards.
      child: EqualHeightColumn(rows: children, separatorColor: palette.glassBorder, separatorIndent: RaynSpacing.lg),
    );
  }
}
