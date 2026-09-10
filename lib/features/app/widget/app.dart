import 'package:accessibility_tools/accessibility_tools.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/features/auth/payment/notifier/iap_launch_reverify.dart';
import 'package:hiddify/features/connection/widget/connection_wrapper.dart';
import 'package:hiddify/features/notifications/notifier/notification_monitor.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/shortcut/shortcut_wrapper.dart';
import 'package:hiddify/features/splash/widget/splash_page.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/widget/window_wrapper.dart';
import 'package:hiddify/hiddifycore/rayn_core_service_provider.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

bool _debugAccessibility = false;

/// Whether [App.onPause] has actually torn the foreground core down.
///
/// Read by [App.onResume] so a resume only rebuilds what a pause closed. The
/// flag has existed since this lifecycle handling was written but was never
/// read, so every resume re-ran full core setup regardless of whether anything
/// had been released.
bool isOnPauseCalled = false;

class App extends HookConsumerWidget with WidgetsBindingObserver, PresLogger {
  const App({super.key});

  /// Deliberately does nothing.
  ///
  /// iOS reports `inactive` for anything that overlays the app WITHOUT
  /// backgrounding it — Control Centre, a notification banner, the app
  /// switcher, and every system sheet, including the camera permission prompt
  /// and the QR scanner. The app is still on screen throughout.
  ///
  /// This used to delegate to [onPause], so all of those released the
  /// foreground core. Each release restarts the core's gRPC server with a
  /// freshly minted TLS certificate, which forcibly terminates any stream
  /// attached to the old one:
  ///
  ///   Stream error in fgLogListener: HTTP/2 error: Connection is being
  ///   forcefully terminated (errorCode: 10)
  ///
  /// A single QR import produced four certificates in 33 seconds that way.
  /// Only `paused` means backgrounded, and only that needs to let the core go.
  void onInactive(WidgetRef ref) {}

  void onPause(WidgetRef ref) {
    if (PlatformUtils.isDesktop) return;
    isOnPauseCalled = true;
    ref.read(raynCoreServiceProvider).closeFront();
  }

  void onResume(WidgetRef ref) {
    // Rebuild only what [onPause] closed. Without this guard a resume set up the
    // core again even when it had never been released — which, before
    // [onInactive] stopped pausing, was most resumes.
    //
    // Desktop never sets the flag (onPause returns early there and closes
    // nothing), so desktop no longer re-initialises on window focus either.
    // That is intended: there is nothing to restore.
    if (!isOnPauseCalled) return;
    isOnPauseCalled = false;
    ref.read(raynCoreServiceProvider).init();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    setupStateListener(ref);
    final router = ref.watch(goRouterNotiferProvider);
    final locale = ref.watch(localePreferencesProvider);
    final themeMode = ref.watch(themePreferencesProvider);
    final theme = AppTheme(themeMode, locale.preferredFontFamily);
    final activeBreakpoint = Breakpoint(context).activeBreakpoint;

    ref.listen(foregroundProfilesUpdateNotifierProvider, (_, _) {});
    // Tray init only when a profile is authenticated. Pre-auth, gRPC has
    // nothing to report and the listener would hang on `serviceRunningProvider`.
    final hasProfile = ref.watch(hasAnyProfileProvider).valueOrNull ?? false;
    if (PlatformUtils.isDesktop && hasProfile) ref.listen(systemTrayNotifierProvider, (_, _) {});
    // Start the notification monitor once authenticated — it watches the active
    // profile's subscription to raise quota/expiry alerts. Pre-auth there is no
    // profile to evaluate.
    if (hasProfile) ref.listen(notificationMonitorProvider, (_, _) {});
    // Re-verify any active Google Play purchase once at launch (Android + an
    // account session). Silent, idempotent, self-guarding — recovers an
    // interrupted purchase or a reinstalled / cross-device subscription. Safe
    // pre-auth: it touches only secure storage + Billing + the auth API, never
    // the gRPC core that the listeners above must wait on.
    ref.listen(iapLaunchReverifyProvider, (_, _) {});

    // updating ActiveBreakpointNotifier value
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeBreakpointNotifierProvider.notifier).update(activeBreakpoint);
      });
      return null;
    }, [activeBreakpoint]);
    return WindowWrapper(
      ShortcutWrapper(
        ToastificationWrapper(
          child: ConnectionWrapper(
            MaterialApp.router(
              routerConfig: router,
              locale: locale.flutterLocale,
              supportedLocales: AppLocaleUtils.supportedLocales,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              debugShowCheckedModeBanner: false,
              themeMode: themeMode.flutterThemeMode,
              theme: theme.lightTheme(),
              darkTheme: theme.darkTheme(),
              title: Constants.appName,
              builder: (context, child) {
                final theme = Theme.of(context);
                // Branded launch screen over the first route. Inside the
                // builder rather than around MaterialApp so it inherits the
                // theme and Directionality, and mobile-only (see SplashGate).
                //
                // Assigned to a local rather than back onto `child`: the
                // parameter reassignment this replaces tripped
                // parameter_assignments, and rebinding a parameter makes the
                // wrapping order harder to follow than it needs to be.
                final Widget content = SplashGate(child: child ?? const SizedBox());
                if (kDebugMode && _debugAccessibility) {
                  return AccessibilityTools(checkFontOverflows: true, child: content);
                }
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: theme.scaffoldBackgroundColor,
                    systemNavigationBarColor: theme.scaffoldBackgroundColor,
                    systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                  ),
                  child: content,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void setupStateListener(WidgetRef ref) {
    final appLifecycleState = useAppLifecycleState();

    useEffect(() {
      loggy.info("current app state");
      loggy.info(appLifecycleState);
      if (appLifecycleState == AppLifecycleState.paused) {
        onPause(ref);
      } else if (appLifecycleState == AppLifecycleState.inactive) {
        onInactive(ref);
      } else if (appLifecycleState == AppLifecycleState.resumed) {
        onResume(ref);
      }
      return null;
    }, [appLifecycleState]);
  }
}
