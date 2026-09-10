import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/rayn_navigation_rail.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/home/widget/sidebar_status.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The app's frame around the shell branches: a sidebar on tablet and
/// desktop, a bottom bar on a phone. Two destinations everywhere, Home and
/// Settings; About is a Settings sub-page on every breakpoint, so the branch
/// list no longer changes shape when a window is resized across 600px.
class RaynShell extends HookConsumerWidget {
  const RaynShell({super.key, required this.navigationShell, required this.isMobileBreakpoint});

  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;
  final bool isMobileBreakpoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // focus switch management
    final primaryFocusHash = useState<int?>(null);
    final navScopeNode = useFocusScopeNode();
    useEffect(() {
      bool handler(KeyEvent event) {
        final arrows = isMobileBreakpoint ? KeyboardConst.verticalArrows : KeyboardConst.horizontalArrows;
        if (!arrows.contains(event.logicalKey)) return false;
        if (event is KeyDownEvent) {
          primaryFocusHash.value = FocusManager.instance.primaryFocus.hashCode;
        } else {
          // focus node does not change => true.
          if (primaryFocusHash.value == FocusManager.instance.primaryFocus.hashCode) {
            if (branchesScope.values.any((node) => node.hasFocus)) {
              navScopeNode.requestFocus();
            } else if (navScopeNode.hasFocus) {
              branchesScope[getNameOfBranch(navigationShell.currentIndex)]?.requestFocus();
            }
          }
        }
        return true;
      }

      HardwareKeyboard.instance.addHandler(handler);
      return () {
        HardwareKeyboard.instance.removeHandler(handler);
      };
    }, [isMobileBreakpoint, navigationShell.currentIndex]);

    final isDesktop = Breakpoint(context).isDesktop();

    return Material(
      child: Scaffold(
        body: isMobileBreakpoint
            ? navigationShell
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FocusScope(
                    node: navScopeNode,
                    child: RaynNavigationRail(
                      extended: isDesktop,
                      destinations: _raynNavRailDests(_actions(t)),
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: (index) => _onTap(context, index),
                      footer: SidebarStatus(extended: isDesktop),
                    ),
                  ),
                  Expanded(child: navigationShell),
                ],
              ),
        bottomNavigationBar: isMobileBreakpoint
            ? FocusScope(
                node: navScopeNode,
                child: _raynBottomNavBar(
                  context: context,
                  selectedIndex: navigationShell.currentIndex,
                  destinations: _navDests(_actions(t)),
                  onDestinationSelected: (index) => _onTap(context, index),
                ),
              )
            : null,
      ),
    );
  }

  // shell route action onTap
  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  /// Home is a shield, not a power button: the power glyph reads as
  /// "disconnect", which is what the orb on that page already does.
  List<ShellRouteAction> _actions(Translations t) => [
    ShellRouteAction(Icons.shield_rounded, t.pages.home.title),
    ShellRouteAction(Icons.settings_rounded, t.pages.settings.title),
  ];

  List<NavigationDestination> _navDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationDestination(icon: Icon(e.icon), label: e.title)).toList();

  List<RaynNavRailDestination> _raynNavRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => RaynNavRailDestination(icon: e.icon, label: e.title)).toList();

  /// Mobile NavigationBar with the same treatment as the rail's items: a
  /// tinted indicator, the icon in the brand amber, the label in the primary
  /// text colour.
  Widget _raynBottomNavBar({
    required BuildContext context,
    required int selectedIndex,
    required List<NavigationDestination> destinations,
    required ValueChanged<int> onDestinationSelected,
  }) {
    final palette = context.rayn;
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: palette.bgSurface,
        indicatorColor: palette.navSelectedFill,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return RaynTypography.label.copyWith(color: selected ? palette.textPrimary : palette.textSecondary);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? palette.accentText : palette.textSecondary, size: 22);
        }),
      ),
      // A hairline top divider separates the bar from the page canvas; in light
      // mode the pale surface would otherwise blend into the pale background.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          destinations: destinations,
          onDestinationSelected: onDestinationSelected,
        ),
      ),
    );
  }
}
