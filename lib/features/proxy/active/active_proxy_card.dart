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
import 'package:hiddify/features/proxy/active/selected_location_notifier.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ActiveProxyFooter extends ConsumerWidget with InfraLogger {
  const ActiveProxyFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Remember the live exit location so the home screen can show where the next
    // connection will land, before any core/tunnel exists. Registered before the
    // early return so it keeps recording across connect/disconnect transitions.
    ref.listen(activeProxyNotifierProvider, (_, next) {
      final proxy = next.valueOrNull;
      if (proxy == null) return;
      final display = activeProxyDisplay(proxy, ref.read(translationsProvider).requireValue);
      // Only remember real, resolved exits — never an auto-selector placeholder
      // ("Lowest Latency") captured before the group has picked a member.
      if (!display.resolved) return;
      ref
          .read(selectedLocationNotifierProvider.notifier)
          .recordActive(display.name, display.countryCode, display.isAutoSelected);
    });

    final connectionState = ref.watch(
      connectionNotifierProvider.select((value) => value.valueOrNull ?? const Disconnected()),
    );
    final activeProxy = ref.watch(activeProxyNotifierProvider.select((value) => value.valueOrNull));
    final t = ref.watch(translationsProvider).requireValue;

    // Pre-connect (or before the core reports an outbound), show the interactive
    // location tile so the user can review — and change — where they'll exit.
    if (connectionState != const Connected() || activeProxy == null) {
      return const SelectedLocationTile();
    }

    final display = activeProxyDisplay(activeProxy, t);
    final displayName = display.name;
    final modeLabel = display.isAutoSelected ? t.pages.proxies.autoSelected : t.pages.proxies.direct;

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
          // Light mode's pale surfaces blend into the pale background — a subtle
          // drop shadow lifts the card so it reads as a surface above the canvas.
          boxShadow: Theme.of(context).brightness == Brightness.light
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 20, offset: const Offset(0, 6))]
              : null,
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

/// Derives the user-facing label and flag country code for an active outbound,
/// plus whether it resolved to a real exit location. Shared by the live tile and
/// the last-location recorder so both render identically.
///
/// `resolved` is false for auto-selector group placeholders ("Lowest Latency",
/// "Auto rotate") and bare unnamed outbounds — e.g. before a `urltest` group has
/// picked a member on first connect — so the recorder never remembers those as a
/// "last location".
({String name, String countryCode, bool resolved, bool isAutoSelected}) activeProxyDisplay(
  OutboundInfo proxy,
  Translations t,
) {
  final proxyType = ProxyType.fromJson(proxy.type);
  final isAutoSelected = proxyType == ProxyType.urltest || proxyType == ProxyType.balancer;
  final countryCode = proxy.ipinfo.countryCode;

  // Balancer: the core doesn't populate `groupSelectedTagDisplay`, so derive the
  // resolved exit from its IP geo ("Tokyo, JP"). Without a city there's no real
  // location to show, so fall back to the mode label rather than a bare country.
  if (proxyType == ProxyType.balancer) {
    final location = _balancerLocationName(proxy);
    if (location != null) {
      return (name: location, countryCode: countryCode, resolved: true, isAutoSelected: true);
    }
    return (name: t.pages.proxies.autoRotate, countryCode: countryCode, resolved: false, isAutoSelected: true);
  }

  // Node tags are generated in final display form by the MW API — show them
  // verbatim. The client does NOT parse the internal tag schema (that would both
  // duplicate MW's work and encode the fleet's naming convention in the client,
  // a cohort-identification surface). A urltest group's resolved member is
  // carried on `groupSelectedTagDisplay`.
  final rawName = proxy.groupSelectedTagDisplay.isNotEmpty ? proxy.groupSelectedTagDisplay : proxy.tagDisplay;

  // Client-injected auto-selector groups have no per-node tag until they resolve
  // a member; give the known ones their mode labels (these are local group tags,
  // not MW-issued node names) and mark them unresolved so the recorder doesn't
  // remember a placeholder.
  switch (rawName.toLowerCase()) {
    case 'lowest':
      return (name: t.pages.proxies.lowestLatency, countryCode: countryCode, resolved: false, isAutoSelected: true);
    case 'balance':
      return (name: t.pages.proxies.autoRotate, countryCode: countryCode, resolved: false, isAutoSelected: true);
  }

  return (
    name: displayNodeTag(rawName),
    countryCode: countryCode,
    resolved: rawName.isNotEmpty,
    isAutoSelected: isAutoSelected,
  );
}

String getRealOutboundTag(OutboundInfo group) {
  var tag = group.tagDisplay;
  if (group.groupSelectedTagDisplay != "" && group.groupSelectedTagDisplay != tag) {
    tag = "$tag → ${group.groupSelectedTagDisplay}";
  }
  return tag;
}

/// Location for a balancer's resolved exit from its IP geo — "City, CC", or just
/// "City" when the country is missing. Returns null when there's no city to build
/// a real location (a bare country reads as a meaningless "JP"); the caller then
/// shows the "Auto rotate" mode label instead.
String? _balancerLocationName(OutboundInfo proxy) {
  final ip = proxy.ipinfo;
  final city = ip.city;
  final cc = ip.countryCode;
  if (city.isNotEmpty && cc.isNotEmpty) return '$city, $cc';
  if (city.isNotEmpty) return city;
  return null;
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

/// Pre-connect counterpart to [ActiveProxyFooter]. Shows the remembered exit
/// location (or a "Select location" prompt on first-ever launch) and — unlike
/// the live footer — is tappable while disconnected: it opens the Proxies page,
/// which renders the cached snapshot so the user can change where they'll exit
/// before connecting. The picked location is applied on the next connect.
class SelectedLocationTile extends ConsumerWidget {
  const SelectedLocationTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedLocationNotifierProvider);
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;

    final hasSelection = selected != null;
    final title = hasSelection ? selected.displayName : t.pages.proxies.selectLocation;
    final subtitle = hasSelection
        ? (selected.isAutoSelected ? t.pages.proxies.autoSelected : t.pages.proxies.direct)
        : t.pages.proxies.tapToChoose;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
      child: Semantics(
        button: true,
        label: '$title: $subtitle',
        child: GlassSurface(
          padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.md, vertical: RaynSpacing.md),
          boxShadow: Theme.of(context).brightness == Brightness.light
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 20, offset: const Offset(0, 6))]
              : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.goNamed('proxies'),
              borderRadius: BorderRadius.circular(RaynRadius.card),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(RaynSpacing.xs),
                    child: hasSelection
                        ? IPCountryFlag(countryCode: selected.countryCode, size: 40)
                        : Icon(Icons.public_outlined, size: 36, color: palette.textSecondary),
                  ),
                  const SizedBox(width: RaynSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: RaynTypography.body.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: RaynTypography.caption.copyWith(color: palette.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: RaynSpacing.sm),
                  Icon(Icons.chevron_right_rounded, size: 22, color: palette.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
