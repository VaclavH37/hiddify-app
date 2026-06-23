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
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';
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

    final proxyType = ProxyType.fromJson(activeProxy.type);
    final isAutoSelected = proxyType == ProxyType.urltest || proxyType == ProxyType.balancer;
    // Balancer rotates across multiple outbounds and the core does not
    // populate `groupSelectedTagDisplay`, so falling back to `tagDisplay`
    // would just print the group's name ("round-robin"). Derive a location
    // from the exit IP info instead — that's what the user actually wants
    // to see for an auto-rotated connection.
    final String rawName;
    if (proxyType == ProxyType.balancer) {
      rawName = _balancerLocationName(activeProxy);
    } else if (activeProxy.groupSelectedTagDisplay.isNotEmpty) {
      rawName = activeProxy.groupSelectedTagDisplay;
    } else {
      rawName = activeProxy.tagDisplay;
    }
    // Transform the backend hub/exit tag (e.g. "EXIT-US-DALLAS-01🇺🇸") into a
    // readable "City, CC" label; fall back to the flag-stripped raw name for
    // group/balancer labels that don't follow the convention.
    final displayName = prettifyNodeName(rawName) ?? stripTrailingFlag(rawName);
    final modeLabel = isAutoSelected ? t.pages.proxies.autoSelected : t.pages.proxies.direct;

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
        label: '${t.pages.proxies.activeProxy}: $displayName',
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
                            displayName,
                            style: RaynTypography.body.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(modeLabel, style: RaynTypography.caption.copyWith(color: context.rayn.textMuted)),
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

/// Builds a location label for a balancer outbound from its exit IP info.
/// Prefers `city, countryCode`, then `city`, then `region`, then
/// `countryCode`; falls back to the group's `tagDisplay` ("round-robin"
/// etc.) only when no geo info is available.
String _balancerLocationName(OutboundInfo proxy) {
  final ip = proxy.ipinfo;
  final city = ip.city;
  final cc = ip.countryCode;
  if (city.isNotEmpty && cc.isNotEmpty) return '$city, $cc';
  if (city.isNotEmpty) return city;
  if (ip.region.isNotEmpty) return ip.region;
  if (cc.isNotEmpty) return cc;
  return proxy.tagDisplay;
}

/// Renders 4 ascending bars whose active count is derived from the active
/// proxy's `urlTestDelay`. Updates are debounced to 1s — the underlying
/// provider can tick frequently and a steady visual is more useful than a
/// jittery one.
class _SignalBars extends HookConsumerWidget {
  const _SignalBars();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = ref.watch(activeProxyNotifierProvider.select((v) => v.valueOrNull?.urlTestDelay ?? 0));
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
    if (delay <= 0) return 0; // untested / no value
    if (delay < 300) return 4; // full bars
    if (delay < 600) return 3; // 300–600ms
    if (delay < 900) return 2; // 600–900ms
    return 1; // 900ms+
  }
}
