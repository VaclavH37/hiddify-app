import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Home-screen entry to the Android split-tunneling configuration (internally
/// `per_app_proxy` — Drift `AppProxyEntries` + preference `per_app_proxy_mode`).
///
/// Why prominent: in restricted regional networks, specific local apps
/// (WeChat, AliPay, regional banking / payment / government services) require
/// direct routing or they break. Without split-tunneling configured, the app
/// is effectively unusable for a large share of our target audience. Burying
/// this three taps deep under Settings → Routing causes measurable drop-off
/// during first-run setup.
///
/// Copy constraint — read before changing any user-facing string on this
/// surface. No label, subtitle, hint, dialog, error, snackbar, or analytics
/// event tied to this widget may reference: censorship, the Great Firewall,
/// the GFW, the country it lives in, sanctions, VPN evasion, or
/// circumvention. Frame this purely as a generic routing / connectivity
/// utility. Approved vocabulary: "Routing Mode", "Split tunneling",
/// "Per-app proxy", "Bypass", "Active" / "Disabled", app-name labels.
class PerAppProxyHomeTile extends ConsumerWidget {
  const PerAppProxyHomeTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final mode = ref.watch(Preferences.perAppProxyMode);
    final isActive = mode.enabled;

    final palette = context.rayn;
    final strings = t.pages.home.actions.routingMode;
    final subtitle = isActive ? strings.subtitleActive : strings.subtitleDisabled;
    final hint = isActive ? strings.hintActive : strings.hintDisabled;
    final statusLabel = isActive ? strings.active : strings.disabled;

    return GlassSurface(
      border: isActive
          ? Border.all(color: palette.warning.withValues(alpha: 0.45))
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: RaynSpacing.md,
        vertical: RaynSpacing.md,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(RaynRadius.card),
          onTap: () async {
            if (!isActive) {
              await ref
                  .read(Preferences.perAppProxyMode.notifier)
                  .update(PerAppProxyMode.exclude);
            }
            if (context.mounted) context.goNamed('perAppProxy');
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.alt_route_rounded,
                    size: 28,
                    color: isActive ? palette.warning : palette.textPrimary,
                  ),
                  const SizedBox(width: RaynSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.title,
                          style: RaynTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: RaynTypography.caption.copyWith(
                            color: palette.textMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: RaynSpacing.sm),
                  _StatusPill(active: isActive, label: statusLabel),
                  const SizedBox(width: RaynSpacing.sm),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 22,
                    color: palette.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: RaynSpacing.md),
              Container(height: 1, color: palette.glassBorder),
              const SizedBox(height: RaynSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: isActive ? palette.warning : palette.textMuted,
                  ),
                  const SizedBox(width: RaynSpacing.xs),
                  Expanded(
                    child: Text(
                      hint,
                      style: RaynTypography.caption.copyWith(
                        color: isActive ? palette.warning : palette.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final fill = active
        ? palette.warning
        : palette.textPrimary.withValues(alpha: 0.08);
    final fg = active ? Colors.black : palette.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RaynSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(RaynRadius.pill),
      ),
      child: Text(
        label,
        style: RaynTypography.caption.copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
