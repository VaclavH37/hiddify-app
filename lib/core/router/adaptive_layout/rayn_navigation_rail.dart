import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_colors.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/gen/assets.gen.dart';

/// Custom navigation rail for the Rayn redesign.
///
/// Stock `NavigationRail` cannot carry the brand block, glass active surface,
/// or gold token-driven typography per item, so we build our own. Only the
/// visuals change — the index/onTap contract matches `NavigationRail`, so the
/// caller still talks to `navigationShell.currentIndex` and `goBranch()`.
class RaynNavigationRail extends StatelessWidget {
  const RaynNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.extended,
    this.trailing,
  });

  final List<RaynNavRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;

  /// Optional widget rendered below the nav items. Intended for the desktop
  /// stats column. Caller is responsible for omitting it when the rail is
  /// collapsed (the [trailing] block won't fit in [_collapsedWidth]).
  final Widget? trailing;

  static const double _extendedWidth = 280;
  static const double _collapsedWidth = 72;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: extended ? _extendedWidth : _collapsedWidth,
      color: context.rayn.bgSurface,
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
                      if (trailing != null) ...[const Spacer(), trailing!],
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
      // Collapsed rail: just the icon — the "RAYN VPN" wordmark won't fit in
      // the 72px column.
      return Center(
        child: Assets.images.logo.image(
          width: 32,
          height: 32,
          color: context.rayn.logoNeutral,
          colorBlendMode: BlendMode.srcIn,
        ),
      );
    }
    // Extended rail: full brand wordmark per WORDMARK.md, compact variant so
    // the icon stays at the rail's established 32px.
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: RaynSpacing.sm),
      child: RaynWordmark(iconSize: 32, wordSize: 24, suffixSize: 14, gap: 6),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.extended, required this.onTap});

  final RaynNavRailDestination destination;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final Color foreground = selected ? RaynColors.goldPrimary : palette.textSecondary;
    final BorderRadius radius = BorderRadius.circular(RaynRadius.button);

    final Widget content = extended
        ? Row(
            children: [
              Icon(destination.icon, size: 22, color: foreground),
              const SizedBox(width: RaynSpacing.md),
              Expanded(
                child: Text(
                  destination.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RaynTypography.body.copyWith(color: foreground),
                ),
              ),
            ],
          )
        : Center(child: Icon(destination.icon, size: 22, color: foreground));

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
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: selected ? palette.navSelectedFill : Colors.transparent,
              borderRadius: radius,
              border: selected ? Border.all(color: palette.navSelectedBorder) : null,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: extended ? RaynSpacing.lg : RaynSpacing.sm,
              vertical: RaynSpacing.md,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
