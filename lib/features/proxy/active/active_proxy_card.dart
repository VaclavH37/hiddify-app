import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ActiveProxyFooter extends ConsumerWidget with InfraLogger {
  const ActiveProxyFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(
      connectionNotifierProvider.select((value) => value.valueOrNull ?? const Disconnected()),
    );
    final activeProxy = ref.watch(activeProxyNotifierProvider.select((value) => value.valueOrNull));
    final t = ref.watch(translationsProvider).requireValue;

    if (connectionState != const Connected() || activeProxy == null) {
      return const SizedBox.shrink();
    }

    Future<void> handleUrlTest() async {
      try {
        if (!context.mounted) return;
        await ref.read(activeProxyNotifierProvider.notifier).urlTest("");
      } catch (e) {
        loggy.error("Error during URL test: $e");
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
      child: Semantics(
        button: true,
        label: '${t.pages.proxies.activeProxy}: ${activeProxy.tagDisplay}',
        child: GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.md, vertical: RaynSpacing.md),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.goNamed('proxies'),
              borderRadius: BorderRadius.circular(RaynRadius.card),
              child: Row(
              children: [
                InkWell(
                  onTap: () async {
                    await handleUrlTest();
                    if (!context.mounted) return;
                    await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: activeProxy);
                  },
                  borderRadius: BorderRadius.circular(RaynRadius.button),
                  child: Padding(
                    padding: const EdgeInsets.all(RaynSpacing.xs),
                    child: IPCountryFlag(
                      countryCode: activeProxy.ipinfo.countryCode,
                      organization: activeProxy.ipinfo.org,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(width: RaynSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: t.pages.proxies.activeProxy,
                        child: Text(
                          activeProxy.tagDisplay,
                          style: RaynTypography.body.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (activeProxy.ipinfo.ip.isNotEmpty)
                        IPText(ip: activeProxy.ipinfo.ip, onLongPress: handleUrlTest, constrained: true)
                      else
                        UnknownIPText(text: t.pages.proxies.unknownIp, onTap: handleUrlTest, constrained: true),
                    ],
                  ),
                ),
                const SizedBox(width: RaynSpacing.sm),
                const _SignalBars(),
                const SizedBox(width: RaynSpacing.sm),
                Icon(Icons.chevron_right_rounded, size: 22, color: context.rayn.textSecondary),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

String getRealOutboundTag(OutboundInfo group) {
  var tag = group.tagDisplay;
  if (group.groupSelectedTagDisplay != "" && group.groupSelectedTagDisplay != tag) {
    tag = "$tag → ${group.groupSelectedTagDisplay}";
  }
  return tag;
}

/// Renders 4 ascending bars whose active count is derived from the active
/// proxy's `urlTestDelay`. Updates are debounced to 1s — the underlying
/// provider can tick frequently and a steady visual is more useful than a
/// jittery one.
class _SignalBars extends HookConsumerWidget {
  const _SignalBars();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = ref.watch(
      activeProxyNotifierProvider.select((v) => v.valueOrNull?.urlTestDelay ?? 0),
    );
    final displayed = useState<int>(delay);

    useEffect(() {
      if (displayed.value == delay) return null;
      final timer = Timer(const Duration(seconds: 1), () {
        displayed.value = delay;
      });
      return timer.cancel;
    }, [delay]);

    final palette = context.rayn;
    final activeBars = _barCount(displayed.value);
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(4, (i) {
          final active = i < activeBars;
          return Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
            child: Container(
              width: 4,
              height: 7.0 + i * 3.0,
              decoration: BoxDecoration(
                color: active ? palette.success : palette.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  int _barCount(int delay) {
    if (delay <= 0) return 0;
    if (delay <= 120) return 4;
    if (delay <= 200) return 3;
    if (delay <= 300) return 2;
    return 1;
  }
}
