import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/adaptive_layout/rayn_shell.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/refresh_listenable.dart';
import 'package:hiddify/features/about/widget/about_page.dart';
import 'package:hiddify/features/auth/delete/widget/delete_account_page.dart';
import 'package:hiddify/features/auth/login/widget/login_page.dart';
import 'package:hiddify/features/auth/notifier/auth_gate_providers.dart';
import 'package:hiddify/features/auth/payment/widget/payment_page.dart';
import 'package:hiddify/features/auth/payment/widget/plan_transition_page.dart';
import 'package:hiddify/features/auth/register/widget/register_page.dart';
import 'package:hiddify/features/auth/register/widget/verify_email_page.dart';
import 'package:hiddify/features/auth/widget/auth_page.dart';
import 'package:hiddify/features/disclosure/widget/data_disclosure_page.dart';
import 'package:hiddify/features/disclosure/widget/vpn_disclosure_page.dart';
import 'package:hiddify/features/home/widget/home_page.dart';
import 'package:hiddify/features/notifications/widget/notifications_inbox_page.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_page.dart';
import 'package:hiddify/features/settings/overview/settings_page.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'routing_config_notifier.g.dart';

// each branch in go router has its own focus scope
final branchesScope = <String, FocusScopeNode>{
  'home': FocusScopeNode(),
  'settings': FocusScopeNode(),
};

// when the routing config is not yet initialized, this config is used
final loadingConfig = RoutingConfig(
  routes: <RouteBase>[GoRoute(path: '/home', builder: (context, state) => const Material())],
);

/// The shell's branches, in rail and bar order, on every breakpoint. About is
/// a Settings sub-page everywhere, so the list no longer changes shape when a
/// window is resized across the mobile breakpoint.
const branchNames = ['home', 'settings'];

String getNameOfBranch(int index) => branchNames[index];

@Riverpod(keepAlive: true)
class RoutingConfigNotifier extends _$RoutingConfigNotifier {
  @override
  RoutingConfig build() {
    final isMobileBreakpoint = ref.watch(isMobileBreakpointProvider);
    if (isMobileBreakpoint == null) return loadingConfig;
    return RoutingConfig(
      redirect: (context, state) {
        // `/auth` and its sub-routes (e.g. `/auth/login`) are all pre-auth
        // surfaces — none should be bounced while unauthenticated.
        final isAuthRoute = state.matchedLocation.startsWith('/auth');

        // Capture an incoming rayn:// URL from either the direct deep-link
        // path or the desktop app-links surface.
        String? url;
        if (LinkParser.protocols.contains(state.uri.scheme)) {
          url = state.uri.toString();
        } else if (PlatformUtils.isDesktop && newUrlFromAppLink.isNotEmpty) {
          url = newUrlFromAppLink;
          newUrlFromAppLink = '';
        }

        // Mobile-only Google Play prominent disclosures, shown before any auth
        // surface. Two SEPARATE consent screens (VpnService, then account
        // data) — the VpnService disclosure must not be combined with the
        // personal-data one. Desktop is exempt (no VpnService, not a Play
        // submission) and falls straight through.
        if (!PlatformUtils.isDesktop) {
          final isDisclosureRoute = state.matchedLocation.startsWith('/disclosure');
          if (!ref.read(Preferences.vpnDisclosureAccepted)) {
            if (url != null) ref.read(pendingDeepLinkUrlProvider.notifier).state = url;
            return state.matchedLocation == '/disclosure/vpn' ? null : '/disclosure/vpn';
          }
          if (!ref.read(Preferences.dataDisclosureAccepted)) {
            if (url != null) ref.read(pendingDeepLinkUrlProvider.notifier).state = url;
            return state.matchedLocation == '/disclosure/data' ? null : '/disclosure/data';
          }
          // Both accepted but still parked on a disclosure route → move on.
          if (isDisclosureRoute) return '/auth';
        }

        // hasAnyProfileProvider is a Stream<bool>. While loading, hold on
        // /auth to avoid bouncing into /home with no profile yet.
        final hasProfileAsync = ref.read(hasAnyProfileProvider);
        final hasProfile = hasProfileAsync.valueOrNull;
        if (hasProfile == null) {
          return isAuthRoute ? null : '/auth';
        }

        if (!hasProfile) {
          if (url != null) {
            ref.read(pendingDeepLinkUrlProvider.notifier).state = url;
          }
          return isAuthRoute ? null : '/auth';
        }

        // Has profile, deep link arrived → reject with toast.
        if (url != null) {
          final t = ref.read(translationsProvider).requireValue;
          ref.read(inAppNotificationControllerProvider).showErrorToast(t.auth.alreadySignedIn);
        }

        if (isAuthRoute) return '/home';
        return null;
      },
      routes: <RouteBase>[
        StatefulShellRoute.indexedStack(
          builder: (_, _, navigationShell) =>
              RaynShell(navigationShell: navigationShell, isMobileBreakpoint: isMobileBreakpoint),
          branches: <StatefulShellBranch>[
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'home',
                  path: '/home',
                  builder: (_, _) => FocusScope(node: branchesScope['home'], child: const HomePage()),
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'proxies',
                      path: '/proxies',
                      builder: (_, _) => const ProxiesOverviewPage(),
                    ),
                    GoRoute(
                      name: 'notifications',
                      path: '/notifications',
                      builder: (_, _) => const NotificationsInboxPage(),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: <GoRoute>[
                GoRoute(
                  name: 'settings',
                  path: '/settings',
                  builder: (context, _) => FocusScope(
                    node: branchesScope['settings'],
                    child: PopScope(
                      canPop: false,
                      onPopInvokedWithResult: (_, _) => context.goNamed('home'),
                      child: const SettingsPage(),
                    ),
                  ),
                  routes: <GoRoute>[
                    GoRoute(
                      name: 'about',
                      path: '/about',
                      builder: (_, _) => const AboutPage(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        // Mobile prominent-disclosure screens (registered on all platforms but
        // only reachable on mobile — desktop skips the redirect gate above).
        GoRoute(
          name: 'vpnDisclosure',
          path: '/disclosure/vpn',
          builder: (_, _) => const VpnDisclosurePage(),
        ),
        GoRoute(
          name: 'dataDisclosure',
          path: '/disclosure/data',
          builder: (_, _) => const DataDisclosurePage(),
        ),
        GoRoute(
          name: 'auth',
          path: '/auth',
          builder: (_, _) => const AuthPage(),
          routes: <GoRoute>[
            GoRoute(name: 'login', path: 'login', builder: (_, _) => const LoginPage()),
            GoRoute(name: 'register', path: 'register', builder: (_, _) => const RegisterPage()),
            // Shown after a `pending_payment` (or `expired`) login: the live
            // Google Play purchase screen (buy → verify → import). `extra == true`
            // selects the expired/renew variant.
            GoRoute(
              name: 'payment',
              path: 'payment',
              builder: (_, state) => PaymentPage(expired: state.extra as bool? ?? false),
            ),
            GoRoute(
              name: 'verifyEmail',
              path: 'verify-email',
              // `extra` carries the typed email (from register success or the
              // login "email not verified" redirect) so resend works.
              builder: (_, state) => VerifyEmailPage(email: state.extra as String? ?? ''),
            ),
          ],
        ),
        // Post-auth full-screen: convert a web-paid (NOWPayments/Guardarian)
        // plan to an auto-renewing Google Play subscription. Reached from
        // Settings → Account for users whose payment provider isn't google_play.
        // Not under `/auth`, so the redirect leaves it alone once a profile exists.
        GoRoute(
          name: 'planTransition',
          path: '/upgrade',
          builder: (_, _) => const PlanTransitionPage(),
        ),
        // Post-auth full-screen: permanent account deletion, required by App
        // Store guideline 5.1.1(v). Outside `/auth` for the same reason as
        // /upgrade — the redirect must leave it alone while a profile exists,
        // because deleting the account is only reachable once you have one.
        GoRoute(
          name: 'deleteAccount',
          path: '/account/delete',
          builder: (_, _) => const DeleteAccountPage(),
        ),
      ],
    );
  }
}
