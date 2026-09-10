import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/gen/assets.gen.dart';

/// The desktop and tablet sidebar: brand, two destinations, and a status
/// footer. Built by hand because the stock `NavigationRail` cannot carry the
/// brand block or a footer; the index/onTap contract matches it, so the shell
/// talks to `navigationShell.currentIndex` and `goBranch()` as before.
///
/// 240 wide when extended (the Material default is 256; 280, the old width,
/// took a third of the default window), 72 when collapsed on a tablet. A
/// hairline on its right edge separates it from the canvas, which on dark is
/// within one level of the rail's own colour.
class RaynNavigationRail extends StatelessWidget {
  const RaynNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.extended,
    this.footer,
  });

  final List<RaynNavRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;

  /// Rendered at the foot of the rail, in both widths; the widget decides
  /// what fits. The shell passes the connection status.
  final Widget? footer;

  static const double extendedWidth = 240;
  static const double collapsedWidth = 72;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Container(
      width: extended ? extendedWidth : collapsedWidth,
      decoration: BoxDecoration(
        color: palette.bgSurface,
        border: Border(right: BorderSide(color: palette.hairline)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.md, vertical: RaynSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _BrandBlock(extended: extended),
                      const SizedBox(height: RaynSpacing.xl),
                      for (int i = 0; i < destinations.length; i++) ...[
                        _NavItem(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          extended: extended,
                          onTap: () => onDestinationSelected(i),
                        ),
                        if (i != destinations.length - 1) const SizedBox(height: RaynSpacing.xs),
                      ],
                      if (footer != null) ...[const Spacer(), footer!],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class RaynNavRailDestination {
  const RaynNavRailDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    if (!extended) {
      // Collapsed rail: just the mark; the wordmark does not fit in 72.
      return Center(
        child: Assets.images.logo.image(
          width: 32,
          height: 32,
          color: context.rayn.logoMark,
          colorBlendMode: BlendMode.srcIn,
        ),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: RaynSpacing.sm),
      child: RaynWordmark(iconSize: 32, wordSize: 24, suffixSize: 14, gap: 6),
    );
  }
}

/// One destination. Selected: a tinted fill, the icon in the brand amber, the
/// label in the primary text colour. No border: the old bordered pill was the
/// same outlined-everything habit the settings rows lost.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.extended, required this.onTap});

  final RaynNavRailDestination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final iconColor = selected ? palette.accentText : palette.textSecondary;
    final labelColor = selected ? palette.textPrimary : palette.textSecondary;
    final radius = BorderRadius.circular(RaynRadius.control);

    final Widget content = extended
        ? Row(
            children: [
              Icon(destination.icon, size: 20, color: iconColor),
              const SizedBox(width: RaynSpacing.md),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RaynTypography.body.copyWith(color: labelColor),
                ),
              ),
            ],
          )
        : Center(child: Icon(destination.icon, size: 20, color: iconColor));

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            decoration: BoxDecoration(color: selected ? palette.navSelectedFill : null, borderRadius: radius),
            padding: EdgeInsets.symmetric(
              horizontal: extended ? RaynSpacing.md : RaynSpacing.sm,
              vertical: RaynSpacing.sm,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
