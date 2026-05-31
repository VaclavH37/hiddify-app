import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_colors.dart';
import 'package:hiddify/core/theme/rayn_motion.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/core/widget/shimmer_skeleton.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int _timeoutThreshold = 65000;

class ActiveProxyDelayIndicator extends HookConsumerWidget with InfraLogger {
  const ActiveProxyDelayIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final activeProxy = ref.watch(activeProxyNotifierProvider);
    final connection = ref.watch(
      connectionNotifierProvider.select((value) => value.valueOrNull ?? const Disconnected()),
    );
    final reduceMotionFlag = reduceMotion(context);

    if (activeProxy is! AsyncData) {
      return const SizedBox();
    }

    final proxy = activeProxy.value!;
    final delay = proxy.urlTestDelay;
    final timeout = delay > _timeoutThreshold;
    final hasValue = delay > 0;

    final isConnecting = connection is Connecting;
    final isConnected = connection is Connected;
    final shouldPulseDot = isConnected && hasValue && !timeout && !reduceMotionFlag;

    final statusColor = _statusColor(
      palette: palette,
      pingMs: hasValue && !timeout ? delay : null,
      isConnecting: isConnecting,
      isTimeout: timeout,
    );

    final glow = useAnimationController(duration: RaynMotion.glowBreath);
    useEffect(() {
      if (reduceMotionFlag) {
        glow.stop();
        glow.value = 0.5;
      } else {
        glow.repeat(reverse: true);
      }
      return null;
    }, [reduceMotionFlag]);

    final pulse = useAnimationController(duration: RaynMotion.dotPulse);
    useEffect(() {
      if (shouldPulseDot) {
        pulse.repeat(reverse: true);
      } else {
        pulse.stop();
        pulse.value = 0;
      }
      return null;
    }, [shouldPulseDot]);

    return Center(
      child: Semantics(
        button: true,
        label: t.pages.proxies.testDelay,
        child: InkWell(
          onTap: () async {
            try {
              await ref.read(activeProxyNotifierProvider.notifier).urlTest("");
            } catch (e) {
              loggy.error("Error during URL test: $e");
            }
          },
          borderRadius: BorderRadius.circular(RaynRadius.pill),
          child: AnimatedBuilder(
            animation: glow,
            builder: (context, child) {
              // Light cream needs a quieter halo than dark — scale the
              // breathing range by the palette's pre-mixed glow alpha.
              final glowMax = palette.goldGlow.a;
              final glowMin = glowMax * 0.6;
              final glowAlpha = reduceMotionFlag ? (glowMax + glowMin) / 2 : glowMin + (glowMax - glowMin) * glow.value;
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(RaynRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: RaynColors.goldPrimary.withValues(alpha: glowAlpha),
                      blurRadius: 32,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: GlassSurface(
              radius: RaynRadius.pill,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.wifi_1_24_regular, size: 18, color: palette.textPrimary),
                  const SizedBox(width: 8),
                  _StatusDot(color: statusColor, pulse: pulse, animate: shouldPulseDot),
                  const SizedBox(width: 8),
                  if (hasValue)
                    _DelayValue(timeout: timeout, delay: delay, t: t, animate: !reduceMotionFlag, palette: palette)
                  else
                    Semantics(
                      label: t.pages.proxies.delay.testing,
                      child: const ShimmerSkeleton(width: 48, height: 18),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor({
    required RaynPalette palette,
    required int? pingMs,
    required bool isConnecting,
    required bool isTimeout,
  }) {
    if (isTimeout) return palette.danger;
    if (isConnecting) return RaynColors.goldPrimary;
    if (pingMs == null) return palette.textMuted;
    if (pingMs < 120) return palette.success;
    if (pingMs < 250) return palette.warning;
    return palette.danger;
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.pulse, required this.animate});

  final Color color;
  final AnimationController pulse;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    if (!animate) return dot;
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.15).animate(CurvedAnimation(parent: pulse, curve: RaynMotion.ambient)),
      child: dot,
    );
  }
}

class _DelayValue extends StatelessWidget {
  const _DelayValue({
    required this.timeout,
    required this.delay,
    required this.t,
    required this.animate,
    required this.palette,
  });

  final bool timeout;
  final int delay;
  final TranslationsEn t;
  final bool animate;
  final RaynPalette palette;

  @override
  Widget build(BuildContext context) {
    if (timeout) {
      return Semantics(
        label: t.pages.proxies.delay.timeout,
        child: Text(t.common.timeout, style: RaynTypography.metric.copyWith(color: palette.danger)),
      );
    }
    final semanticsLabel = t.pages.proxies.delay.result(delay: delay);
    if (!animate) {
      return _delayText(value: delay, semanticsLabel: semanticsLabel);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: delay, end: delay),
      duration: RaynMotion.medium,
      builder: (context, value, _) => _delayText(value: value, semanticsLabel: semanticsLabel),
    );
  }

  Widget _delayText({required int value, required String semanticsLabel}) {
    return Text.rich(
      semanticsLabel: semanticsLabel,
      TextSpan(
        children: [
          TextSpan(
            text: value.toString(),
            style: RaynTypography.metric.copyWith(color: palette.textPrimary),
          ),
          TextSpan(
            text: ' ms',
            style: RaynTypography.metricUnit.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
