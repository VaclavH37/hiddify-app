import 'package:flutter/material.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_bottom_actions.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeProfile = ref.watch(activeProfileProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark ? const Color(0xFF09090B) : null,
          image: const DecorationImage(
            image: AssetImage('assets/images/world_map.png'),
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
                          switch (activeProfile) {
                            AsyncData(value: final profile?) => ProfileTile(
                              profile: profile,
                              isMain: true,
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              color: Theme.of(context).colorScheme.surfaceContainer,
                            ),
                            _ => const Text(""),
                          },
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Stack(
                              children: [
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [ConnectionButton(), ActiveProxyDelayIndicator()],
                                  ),
                                ),
                                Align(
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
                child: HomeBottomActions(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
