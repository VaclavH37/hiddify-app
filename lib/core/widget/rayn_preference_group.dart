import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';

/// A bordered, rounded container holding a vertical column of
/// [RaynSettingsTile]s on the settings sub-pages (General, Routing, DNS,
/// Inbound).
///
/// Visual contract:
/// - Fill drawn from `palette.groupFill` — one step further from
///   `palette.pageBackground` (darker in light mode, lighter in dark mode).
/// - 1px hairline border using `palette.glassBorder`.
/// - [RaynRadius.card] corners; the [ClipRRect] also clips ink ripples
///   inside child tiles to the rounded outline, so the first and last rows
///   ripple into the corners cleanly.
class RaynPreferenceGroup extends StatelessWidget {
  const RaynPreferenceGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final radius = BorderRadius.circular(RaynRadius.card);

    final rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: 60,
          color: palette.glassBorder,
        ));
      }
      rows.add(children[i]);
    }

    return Container(
      decoration: BoxDecoration(
        color: palette.groupFill,
        borderRadius: radius,
        border: Border.all(color: palette.glassBorder),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}
