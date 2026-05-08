import 'package:flutter/material.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_bottom_actions.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark ? const Color(0xFF09090B) : null,
          image: DecorationImage(
            image: AssetImage(
              theme.brightness == Brightness.dark
                  ? 'assets/images/constellation_dark.png'
                  : 'assets/images/constellation_light.png',
            ),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 600,
                  ),
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
                                const Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ActiveProxyFooter(),
                                      SizedBox(height: HomeBottomActions.reservedHeight),
                                    ],
                                  ),
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
              const Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(top: false, child: HomeBottomActions()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
