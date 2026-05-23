import 'package:flutter/material.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Matches one or more trailing country-flag emojis (pairs of regional
/// indicator symbols U+1F1E6–U+1F1FF) plus any surrounding whitespace, so we
/// can strip the redundant flag the backend appends to `tagDisplay` — the
/// flag is already shown as the leading icon.
final RegExp _trailingFlagPattern = RegExp(
  r'\s*(?:[\u{1F1E6}-\u{1F1FF}]{2}\s*)+$',
  unicode: true,
);

class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap});

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.rayn;

    var displayName = proxy.tagDisplay.replaceAll(_trailingFlagPattern, '');
    if (proxy.isGroup && displayName.isNotEmpty) {
      if (displayName.toLowerCase() == 'balance') {
        displayName = 'Auto rotate';
      } else {
        displayName = displayName[0].toUpperCase() + displayName.substring(1);
      }
    }

    final titleStyle = RaynTypography.body.copyWith(color: palette.textPrimary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () async =>
            await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
        borderRadius: BorderRadius.circular(RaynRadius.card),
        child: GlassSurface(
          padding: const EdgeInsets.symmetric(
            horizontal: RaynSpacing.lg,
            vertical: RaynSpacing.md,
          ),
          fillColor: selected ? AppTheme.brandAccent.withValues(alpha: 0.16) : null,
          border: selected
              ? Border.all(color: AppTheme.brandAccent.withValues(alpha: 0.55))
              : null,
          child: Row(
            children: [
              IPCountryFlag(
                countryCode: proxy.ipinfo.countryCode,
                organization: proxy.ipinfo.org,
                size: 40,
              ),
              const SizedBox(width: RaynSpacing.md),
              Expanded(
                child: Text(displayName, overflow: TextOverflow.ellipsis, style: titleStyle),
              ),
              if (proxy.urlTestDelay != 0) ...[
                const SizedBox(width: RaynSpacing.md),
                Text(
                  proxy.urlTestDelay > 65000 ? "×" : proxy.urlTestDelay.toString(),
                  style: RaynTypography.caption.copyWith(
                    color: _delayColor(palette, proxy.urlTestDelay),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _delayColor(RaynPalette palette, int delay) {
    if (delay < 800) return palette.success;
    if (delay < 1500) return palette.warning;
    return palette.danger;
  }
}
