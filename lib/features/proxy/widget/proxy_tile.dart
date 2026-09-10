import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/model/node_name.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap});

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.rayn;
    final t = ref.watch(translationsProvider).requireValue;

    final String displayName;
    if (proxy.isGroup) {
      // Group rows: surface the client-injected auto-selector groups with
      // friendly mode labels ("lowest" → Lowest Latency, "balance" → Auto
      // rotate); any other group name is shown verbatim.
      final tag = proxy.tagDisplay;
      switch (tag.toLowerCase()) {
        case 'lowest':
          displayName = t.pages.proxies.lowestLatency;
        case 'balance':
          displayName = t.pages.proxies.autoRotate;
        default:
          displayName = tag;
      }
    } else {
      // Node rows: the readable name is authored by the MW API and shown as-is;
      // only the "EXIT-" role prefix and a trailing country-flag emoji are
      // stripped (the flag is drawn separately as the leading icon). The internal
      // tag schema is not otherwise parsed.
      displayName = displayNodeTag(proxy.tagDisplay);
    }

    final titleStyle = RaynTypography.body.copyWith(color: palette.textPrimary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RaynRadius.card),
        child: RaynSurface(
          padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
          fillColor: selected ? AppTheme.brandAccent.withValues(alpha: 0.16) : null,
          border: selected ? Border.all(color: AppTheme.brandAccent.withValues(alpha: 0.55)) : null,
          child: Row(
            children: [
              IPCountryFlag(countryCode: proxy.ipinfo.countryCode, organization: proxy.ipinfo.org, size: 40),
              const SizedBox(width: RaynSpacing.md),
              Expanded(
                child: Text(displayName, overflow: TextOverflow.ellipsis, style: titleStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
