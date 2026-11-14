import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';

/// Owns the system back press for the whole shell.
///
/// It has to sit on the visible shell, and nowhere inside a branch. Branches
/// stay mounted after the user leaves them, and go_router (16.x) wraps each
/// branch's navigator in a `PopScope` whose `canPop` is false while that branch
/// has a sub-page open. Leave Settings with About still open and that inactive
/// branch vetoes every back press in the app: the press is swallowed and back
/// can no longer close the app (flutter/flutter#193098, fixed in go_router only
/// after this was written). A `PopScope` of our own inside the Settings branch
/// stayed mounted the same way.
///
/// `canPop` is always false, so the press always reaches [onPopInvokedWithResult]
/// here instead of Android closing the app without calling Flutter. A press a
/// branch can handle itself, such as closing About, is popped by go_router
/// before it gets here, so this only sees presses at the root of a branch.
class ShellBackHandler extends StatelessWidget {
  const ShellBackHandler({super.key, required this.navigationShell, required this.child});

  final StatefulNavigationShell navigationShell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final homeIndex = branchNames.indexOf('home');
        if (navigationShell.currentIndex != homeIndex) {
          // Another branch's root: go Home rather than leave the app.
          navigationShell.goBranch(homeIndex);
        } else {
          // Home's root: the way out. The same call the framework makes itself
          // when nothing handles a back press.
          SystemNavigator.pop();
        }
      },
      // Keeps the platform told that Flutter handles back. Each branch navigator
      // broadcasts whether it can handle a press and the last broadcast wins, so
      // popping a page inside a branch can leave "cannot handle" as the final
      // word. Android then closes the app on the next press without calling
      // Flutter. The PopScope above always handles it, so replace that report.
      child: NotificationListener<NavigationNotification>(
        onNotification: (notification) {
          if (notification.canHandlePop) return false;
          const NavigationNotification(canHandlePop: true).dispatch(context);
          return true;
        },
        child: child,
      ),
    );
  }
}
