import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_top_bar.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              image: DecorationImage(image: AssetImage(asset), fit: BoxFit.cover),
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
        ],
      ),
    );
  }
}
