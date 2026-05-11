import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_colors.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Vertical stack of three glass cards (Protected, Traffic, Quota) replacing
/// the old desktop sidebar overview. The widget itself just stacks; the
/// caller decides where it sits (left column on desktop, stacked block on
/// mobile per §1 of the implementation plan).
class StatsColumn extends ConsumerWidget {
  const StatsColumn({super.key, this.showQuota = true});

  /// When false, the Monthly quota card is omitted. Mobile hides it because
  /// the same value is already reachable from Settings; desktop keeps it
  /// since the sidebar has the room.
  final bool showQuota;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ProtectedCard(),
        const SizedBox(height: RaynSpacing.md),
        const _TrafficCard(),
        if (showQuota) ...[
          const SizedBox(height: RaynSpacing.md),
          const _QuotaCard(),
        ],
      ],
    );
  }
}

class _ProtectedCard extends ConsumerWidget {
  const _ProtectedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final connection = ref.watch(
      connectionNotifierProvider.select((value) => value.valueOrNull ?? const Disconnected()),
    );
    final isProtected = connection is Connected;

    final palette = context.rayn;
    final accent = isProtected ? palette.success : palette.danger;
    final title = isProtected ? t.connection.protected : t.connection.unprotected;
    final subtitle = isProtected ? t.connection.secureSubtitle : t.connection.exposedSubtitle;

    return GlassSurface(
      child: Row(
        children: [
          Icon(FluentIcons.shield_24_filled, size: 28, color: accent),
          const SizedBox(width: RaynSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: RaynTypography.body.copyWith(color: accent, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: RaynTypography.caption.copyWith(color: palette.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficCard extends ConsumerWidget {
  const _TrafficCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();

    final palette = context.rayn;
    final uploadSpeed = stats.uplink.toInt().speed();
    final downloadSpeed = stats.downlink.toInt().speed();
    final totalDownload = stats.downlinkTotal.toInt().size();

    return GlassSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.components.stats.trafficLive,
            style: RaynTypography.label.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: RaynSpacing.xs),
          _SpeedRow(
            icon: FluentIcons.arrow_up_16_filled,
            iconColor: palette.success,
            value: uploadSpeed,
            semanticLabel: t.components.stats.uplink,
          ),
          const SizedBox(height: RaynSpacing.xs),
          _SpeedRow(
            icon: FluentIcons.arrow_down_16_filled,
            iconColor: palette.danger,
            value: downloadSpeed,
            semanticLabel: t.components.stats.downlink,
          ),
          const SizedBox(height: RaynSpacing.sm),
          _TrafficRow(
            icon: FluentIcons.arrow_bidirectional_up_down_16_filled,
            iconColor: palette.textSecondary,
            label: t.components.stats.trafficTotal,
            value: totalDownload,
          ),
        ],
      ),
    );
  }
}

class _SpeedRow extends StatelessWidget {
  const _SpeedRow({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.semanticLabel,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Row(
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: RaynSpacing.sm),
          Expanded(child: Text(value, style: RaynTypography.body)),
        ],
      ),
    );
  }
}

class _TrafficRow extends StatelessWidget {
  const _TrafficRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: RaynSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: RaynTypography.label.copyWith(color: palette.textSecondary),
          ),
        ),
        Text(value, style: RaynTypography.body),
      ],
    );
  }
}

class _QuotaCard extends ConsumerWidget {
  const _QuotaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final subInfo = switch (profile) {
      RemoteProfileEntity(:final subInfo) => subInfo,
      _ => null,
    };
    if (subInfo == null) return const SizedBox.shrink();

    final palette = context.rayn;
    final isInfinite = subInfo.total > 10 * 1099511627776;
    final consumedText = subInfo.consumption.sizeGB();
    final totalLabel = isInfinite ? '/ ∞ GiB' : '/ ${subInfo.total.sizeGB()}';
    final percentUsed = (subInfo.ratio * 100).toStringAsFixed(1);
    final daysLeft = subInfo.remaining.inDays;
    final isExpired = subInfo.isExpired;

    return GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.components.subscriptionInfo.monthlyQuota,
            style: RaynTypography.label.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: RaynSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(consumedText, style: RaynTypography.display),
              const SizedBox(width: RaynSpacing.xs),
              Flexible(
                child: Text(
                  totalLabel,
                  style: RaynTypography.label.copyWith(color: palette.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: RaynSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(RaynRadius.pill),
            child: LinearProgressIndicator(
              value: subInfo.ratio,
              minHeight: 4,
              color: RaynColors.goldPrimary,
              backgroundColor: palette.glassBorder,
            ),
          ),
          const SizedBox(height: RaynSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.components.subscriptionInfo.percentUsed(percent: percentUsed),
                style: RaynTypography.caption.copyWith(color: palette.textMuted),
              ),
              Text(
                isExpired
                    ? t.components.subscriptionInfo.expired
                    : t.components.subscriptionInfo.daysLeft(days: daysLeft),
                style: RaynTypography.caption.copyWith(
                  color: isExpired ? palette.danger : RaynColors.goldPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
