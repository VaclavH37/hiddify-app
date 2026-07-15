import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_top_bar.dart';
import 'package:hiddify/features/notifications/widget/notification_banner.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/features/proxy/active/proxy_snapshot_notifier.dart';
import 'package:hiddify/features/proxy/active/selected_location_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the pre-connect location machinery alive regardless of connection
    // state or which sub-screen is visible: the snapshot notifier captures the
    // live proxy group while connected (so the list is available offline), and
    // the selected-location notifier applies a pending pre-connect pick when the
    // tunnel comes up. `listen` (not `watch`) instantiates + keeps them alive
    // without rebuilding the home page on every capture.
    ref.listen(proxySnapshotNotifierProvider, (_, _) {});
    ref.listen(selectedLocationNotifierProvider, (_, _) {});

    final isMobile = Breakpoint(context).isMobile();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.rayn;

    final asset = isDark ? 'assets/images/constellation_dark.png' : 'assets/images/constellation_light.png';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: palette.textPrimary),
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: isMobile ? const HomeMobileAppBar() : null,
          body: Container(
            decoration: BoxDecoration(
              color: palette.bgPrimary,
              image: DecorationImage(
                image: AssetImage(asset),
                fit: BoxFit.cover,
                // Soften the warm constellation/glow wash in light mode so it
                // reads as a subtle accent rather than a haze behind the content.
                opacity: isDark ? 1 : 0.6,
              ),
            ),
            child: isMobile ? const _HomeMobileBody() : const _HomeDesktopBody(),
          ),
        ),
      ),
    );
  }
}

/// Desktop / tablet layout: orb centered in the canvas, ping pill and
/// server card positioned relative to it, top-right bell as a fixed overlay.
/// Stats column lives in the sidebar on desktop, so it does not appear here.
class _HomeDesktopBody extends StatelessWidget {
  const _HomeDesktopBody();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: CustomScrollView(
              slivers: [
                MultiSliver(
                  children: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Stack(
                        children: [
                          const Center(child: ConnectionButton()),
                          // Below the circle (74) + label gap (16) + label (~28) +
                          // gap (8) + half indicator (24) = 150.
                          Center(
                            child: Transform.translate(
                              offset: const Offset(0, 150),
                              child: const SizedBox(height: 48, child: ActiveProxyDelayIndicator()),
                            ),
                          ),
                          // Pill bottom (+174) + 16 gap + half card (~50) = 240.
                          Center(
                            child: Transform.translate(offset: const Offset(0, 240), child: const ActiveProxyFooter()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Positioned just below the top-right bell (HomeTopBarBell): the bell
        // sits at RaynSpacing.lg from the safe-area top and is ~a min tap target
        // (kMinInteractiveDimension) tall, so clear that band before the banner.
        const Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                RaynSpacing.md,
                RaynSpacing.lg + kMinInteractiveDimension + RaynSpacing.sm,
                RaynSpacing.md,
                0,
              ),
              child: NotificationBanner(),
            ),
          ),
        ),
        const HomeTopBarBell(),
      ],
    );
  }
}

/// Mobile layout. Orb is positioned at the exact vertical+horizontal centre
/// of the body; ping pill and server card overlay below it via the same
/// `Transform.translate` pattern desktop uses. Stats live in Settings on
/// mobile (Protected / Live traffic / Monthly quota are all hidden here).
class _HomeMobileBody extends StatelessWidget {
  const _HomeMobileBody();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Stack(
        children: [
          const Center(child: ConnectionButton()),
          // Below the circle (74) + label gap (16) + label (~28) +
          // gap (8) + half indicator (24) = 150.
          Center(
            child: Transform.translate(
              offset: const Offset(0, 150),
              child: const SizedBox(height: 48, child: ActiveProxyDelayIndicator()),
            ),
          ),
          // Pill bottom (+174) + 16 gap + half card (~50) = 240.
          Center(
            child: Transform.translate(offset: const Offset(0, 240), child: const ActiveProxyFooter()),
          ),
          // Just below the mobile app bar / bell (HomeMobileAppBar). The body's
          // outer SafeArea has top:false, so wrap in a SafeArea here to add the
          // status-bar inset — without it, offsetting by kToolbarHeight alone
          // omits the status bar height and the banner rides up under the bell.
          const Align(
            alignment: Alignment.topCenter,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(RaynSpacing.md, kToolbarHeight + RaynSpacing.sm, RaynSpacing.md, 0),
                child: NotificationBanner(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
