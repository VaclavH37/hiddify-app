import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One row of the location picker: flag, name, its latency when known, and
/// a check on the current choice. A flat row inside a `RaynSettingsGroup`,
/// like every other list in the app; it used to be a card of its own with an
/// amber fill and border when selected.
class ProxyTile extends ConsumerWidget {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap});

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.rayn;
    final t = ref.watch(translationsProvider).requireValue;

    // Group rows are the client-injected automatic modes; node rows show the
    // name the middleware authored, with only the role prefix and a trailing
    // flag emoji stripped. The tag schema is not otherwise parsed.
    final mode = proxy.isGroup ? ExitMode.forGroupTag(proxy.tagDisplay) : null;
    final displayName = proxy.isGroup ? (mode?.caption(t) ?? proxy.tagDisplay) : displayNodeTag(proxy.tagDisplay);

    // A failed probe says so; an unprobed exit says nothing. Both used to
    // render blank, so the dead exit "Fastest server" kept picking looked like
    // one that had not been measured yet.
    final delay = proxy.urlTestDelay;
    final (String? latency, String? semantics, Color? colour) = switch (proxy.isGroup
        ? DelayClass.untested
        : delayClassOf(delay)) {
      DelayClass.untested => (null, null, null),
      DelayClass.failed => (t.pages.proxies.delay.noResponse, t.pages.proxies.delay.timeout, palette.danger),
      DelayClass.measured => ('$delay ms', t.pages.proxies.delay.result(delay: delay), palette.textSecondary),
    };

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.lg),
              child: Row(
                children: [
                  if (proxy.isGroup)
                    Icon(
                      mode == ExitMode.rotate ? Icons.shuffle_rounded : Icons.bolt_rounded,
                      size: 28,
                      color: palette.textSecondary,
                    )
                  else
                    IPCountryFlag(countryCode: flagCountryCode(proxy), size: 28, rounded: true),
                  const SizedBox(width: RaynSpacing.lg),
                  Expanded(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: RaynTypography.metric.copyWith(fontWeight: FontWeight.w500, color: palette.textPrimary),
                    ),
                  ),
                  if (latency != null) ...[
                    const SizedBox(width: RaynSpacing.md),
                    Text(
                      latency,
                      semanticsLabel: semantics,
                      style: RaynTypography.body.copyWith(
                        color: colour,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (selected) ...[
                    const SizedBox(width: RaynSpacing.md),
                    Icon(Icons.check_rounded, size: 24, color: palette.accentText),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
