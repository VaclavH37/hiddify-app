import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/active/selected_location_notifier.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
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

    return Semantics(
      button: true,
      label: '${t.pages.proxies.activeProxy}: $displayName',
      child: RaynSurface(
        padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.md, vertical: RaynSpacing.md),
        elevated: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.goNamed('proxies'),
            // Re-test and show the outbound's details. This used to hang off a
            // second InkWell on the flag, nested inside the row's own; a target
            // nobody can see inside a target everybody taps is a mis-tap trap.
            onLongPress: () async {
              await handleUrlTest();
              if (!context.mounted) return;
              await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: activeProxy);
            },
            borderRadius: BorderRadius.circular(RaynRadius.card),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(RaynSpacing.xs),
                  child: IPCountryFlag(
                    countryCode: activeProxy.ipinfo.countryCode,
                    organization: activeProxy.ipinfo.org,
                    size: 40,
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
                const SizedBox(width: RaynSpacing.md),
                const _LatencyLabel(),
                const SizedBox(width: RaynSpacing.sm),
                Icon(Icons.chevron_right_rounded, size: 22, color: context.rayn.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The active outbound's URL-test latency as plain text: "21 ms" while
/// healthy, coloured only once it degrades, "Measuring…" before the first
/// answer, "No response" when the test times out.
///
/// This is the one encoding of the number on the page. It replaced a glass
/// pill with a pulsing dot next to four signal bars on this row: three
/// pictures of one value, on two different colour scales. The thresholds here
/// are the pill's (300 / 600 ms).
class _LatencyLabel extends ConsumerWidget {
  const _LatencyLabel();

  /// URL-test delays at or above this are the core's "no answer" sentinel.
  static const int _timeout = 65000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final delay = ref.watch(activeProxyNotifierProvider.select((value) => value.valueOrNull?.urlTestDelay ?? 0));

    final (String text, String semantics, Color colour) = switch (delay) {
      <= 0 => (t.pages.proxies.delay.measuring, t.pages.proxies.delay.testing, palette.textMuted),
      >= _timeout => (t.pages.proxies.delay.noResponse, t.pages.proxies.delay.timeout, palette.danger),
      < 300 => ('$delay ms', t.pages.proxies.delay.result(delay: delay), palette.textSecondary),
      < 600 => ('$delay ms', t.pages.proxies.delay.result(delay: delay), palette.warning),
      _ => ('$delay ms', t.pages.proxies.delay.result(delay: delay), palette.danger),
    };

    return Text(
      text,
      semanticsLabel: semantics,
      // Tabular figures keep the row from shifting when the value changes.
      style: RaynTypography.body.copyWith(color: colour, fontFeatures: const [FontFeature.tabularFigures()]),
    );
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

    return Semantics(
      button: true,
      label: '$title: $subtitle',
      child: RaynSurface(
        padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.md, vertical: RaynSpacing.md),
        elevated: true,
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
    );
  }
}
