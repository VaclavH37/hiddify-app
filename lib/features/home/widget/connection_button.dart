import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/dialog/widgets/custom_alert_dialog.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/animated_text.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// TODO: rewrite
class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final activeProxy = ref.watch(activeProxyNotifierProvider);
    final delay = activeProxy.valueOrNull?.urlTestDelay ?? 0;

    final requiresReconnect = ref.watch(configOptionNotifierProvider).valueOrNull;
    // final animationController = useAnimationController(
    //   duration: const Duration(seconds: 1),
    // )..repeat(reverse: true); // Ensure the animation loops indefinitely

    //   // Listen to the animation's value
    //   final animationValue = useAnimation(Tween<double>(begin: 0.8, end: 1).animate(animationController));

    //   // useEffect(() {
    //   //   if (true) {
    //   // Start repeating animation
    //   //   } else {
    //   //     animationController.stop(); // Stop animation if connected, disconnected, or error
    //   //   }

    //   //   // Cleanup when widget is disposed
    //   //   return animationController.dispose;
    //   // }, [connectionStatus.value]);

    //   // ref.listen(
    //   //   connectionNotifierProvider,
    //   //   (_, next) {
    //   //     if (next case AsyncError(:final error)) {
    //   //       CustomAlertDialog.fromErr(t.presentError(error)).show(context);
    //   //     }
    //   //     if (next case AsyncData(value: Disconnected(:final connectionFailure?))) {
    //   //       CustomAlertDialog.fromErr(t.presentError(connectionFailure)).show(context);
    //   //     }
    //   //   },
    //   // );

    final isLight = Theme.of(context).brightness == Brightness.light;
    final palette = context.rayn;

    //   // return CircleDesignWidget(
    //   //   onTap: switch (connectionStatus) {
    //   //     // AsyncData(value: Disconnected()) || AsyncError() => () async {
    //   //     //     if (await showExperimentalNotice()) {
    //   //     //       return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    //   //     //     }
    //   //     //   },
    //   //     // AsyncData(value: Connected()) => () async {
    //   //     //     if (requiresReconnect == true && await showExperimentalNotice()) {
    //   //     //       return await ref.read(connectionNotifierProvider.notifier).reconnect(await ref.read(activeProfileProvider.future));
    //   //     //     }
    //   //     //     return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    //   //     //   },
    //   //     _ => () {},
    //   //   },
    //   //   // enabled: switch (connectionStatus) {
    //   //   //   AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
    //   //   //   _ => false,
    //   //   // },
    //   //   // label: switch (connectionStatus) {
    //   //   //   AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
    //   //   //   AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => t.connection.connecting,
    //   //   //   AsyncData(value: final status) => status.present(t),
    //   //   //   _ => "",
    //   //   // },
    //   //   color: switch (connectionStatus) {
    //   //     AsyncData(value: Connected()) when requiresReconnect == true => Colors.teal,
    //   //     AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => Color.fromARGB(255, 157, 139, 1),
    //   //     AsyncData(value: Connected()) => Colors.green.shade900,
    //   //     AsyncData(value: _) => Colors.indigo.shade700, // Color(0xFF3446A5), //buttonTheme.idleColor!,
    //   //     _ => Colors.red,
    //   //   },

    //   //   animated: true ||
    //   //       switch (connectionStatus) {
    //   //         AsyncData(value: Connected()) when requiresReconnect == true => false,
    //   //         AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => false,
    //   //         AsyncData(value: Connected()) => true,
    //   //         AsyncData(value: _) => true,
    //   //         _ => false,
    //   //       },
    //   //   animationValue: animationValue,
    //   // );
    // }
    const secureLabel = "";
    return _ConnectionButton(
      onTap: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => () async {
          final activeProfile = await ref.read(activeProfileProvider.future);
          return await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
        },
        AsyncData(value: Disconnected()) || AsyncError() => () async {
          // Auth gate guarantees a profile exists by the time the home page
          // is reachable; defensive null guard just no-ops.
          if (ref.read(activeProfileProvider).valueOrNull == null) return;
          if (await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
            return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
          }
        },
        AsyncData(value: Connected()) => () async {
          if (requiresReconnect == true &&
              await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) {
            return await ref
                .read(connectionNotifierProvider.notifier)
                .reconnect(await ref.read(activeProfileProvider.future));
          }
          return await ref.read(connectionNotifierProvider.notifier).toggleConnection();
        },
        _ => () {},
      },
      enabled: switch (connectionStatus) {
        AsyncData(value: Connected()) || AsyncData(value: Disconnected()) || AsyncError() => true,
        _ => false,
      },
      label: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => t.connection.reconnect,
        AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => t.connection.connecting,
        AsyncData(value: final status) => status.present(t),
        _ => "",
      },
      // Tints the logo silhouette (BlendMode.srcIn, below), so this switch IS
      // the state indicator. Values come from RaynPalette rather than inline
      // hex so the desktop tray icons, which are pre-rendered at these same
      // colours, cannot drift away from the in-app tint.
      //
      // The two `when` guards keep their ad-hoc colours: they are sub-states of
      // Connected ("reconnect to apply" and "connected but no usable delay")
      // and have no brand colour assigned yet. Amber would make them
      // indistinguishable from a healthy connection.
      buttonColor: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => Colors.teal,
        AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => const Color.fromARGB(255, 185, 176, 103),
        AsyncData(value: Connected()) => palette.stateConnected,
        // Both transitions share one colour, matching how the tray treats them.
        AsyncData(value: Connecting()) => palette.stateConnecting,
        AsyncData(value: Disconnecting()) => palette.stateConnecting,
        AsyncData(value: Disconnected()) => palette.stateDisconnected,
        AsyncError() => palette.stateError,
        // AsyncLoading, and any ConnectionStatus added later. Previously this
        // fell through to a bare `Colors.red`, so the orb flashed red during
        // the initial load before the first status arrived.
        _ => palette.stateDisconnected,
      },
      backgroundColor: switch (connectionStatus) {
        AsyncData(value: Disconnected()) => isLight ? Colors.white : const Color(0xFFF4F4F5),
        _ => Colors.white,
      },
      borderSide: isLight ? const BorderSide(color: Color(0xFFEFE6D9)) : BorderSide.none,
      glowAlpha: isLight ? 0.35 : 0.5,
      animated: switch (connectionStatus) {
        AsyncData(value: Connected()) when requiresReconnect == true => false,
        AsyncData(value: Connected()) when delay <= 0 || delay >= 65000 => false,
        AsyncData(value: Connected()) => true,
        AsyncData(value: _) => true,
        _ => false,
      },
      secureLabel: secureLabel,
    );
  }
}

class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.onTap,
    required this.enabled,
    required this.label,
    required this.buttonColor,
    required this.backgroundColor,
    required this.animated,
    required this.secureLabel,
    this.borderSide = BorderSide.none,
    this.glowAlpha = 0.5,
  });

  final VoidCallback onTap;
  final bool enabled;
  final String label;
  final Color buttonColor;
  final Color backgroundColor;
  final String secureLabel;

  final bool animated;

  /// 1 px border around the orb. Used in light mode so the white circle
  /// reads against cream.
  final BorderSide borderSide;

  /// Glow halo intensity. Softer on light to avoid blowing out cream.
  final double glowAlpha;

  @override
  Widget build(BuildContext context) {
    // Layout box is the 148×148 circle so callers can center on the circle
    // itself; the status label below is rendered as an overflow overlay.
    return RepaintBoundary(
      child: SizedBox(
        width: 148,
        height: 148,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Semantics(
                button: true,
                enabled: enabled,
                label: label,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(blurRadius: 16, color: buttonColor.withValues(alpha: glowAlpha))],
                  ),
                  child: Material(
                    key: const ValueKey("home_connection_button"),
                    shape: CircleBorder(side: borderSide),
                    color: backgroundColor,
                    child: InkWell(
                      focusColor: Colors.grey,
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: TweenAnimationBuilder(
                          tween: ColorTween(end: buttonColor),
                          duration: const Duration(milliseconds: 600),
                          builder: (context, value, child) =>
                              Assets.images.logo.image(color: value, colorBlendMode: BlendMode.srcIn),
                        ),
                      ),
                    ),
                  ).animate(target: enabled ? 0 : 1).blurXY(end: 1),
                ).animate(target: enabled ? 0 : 1).scaleXY(end: .88, curve: Curves.easeIn),
              ),
            ),
            Positioned(
              top: 148 + 16,
              left: -100,
              right: -100,
              child: Center(
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedText(label, style: Theme.of(context).textTheme.titleMedium),
                      if (secureLabel.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              FontAwesomeIcons.shieldHalved,
                              size: 16,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const Gap(4),
                            Text(
                              secureLabel,
                              style: Theme.of(
                                context,
                              ).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.secondary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
