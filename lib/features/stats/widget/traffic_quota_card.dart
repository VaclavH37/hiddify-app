import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TrafficQuotaCard extends HookConsumerWidget {
  const TrafficQuotaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final subInfo = switch (profile) {
      RemoteProfileEntity(:final subInfo) => subInfo,
      _ => null,
    };
    if (subInfo == null) return const SizedBox.shrink();

    final isInfinite = subInfo.total > 10 * 1099511627776;
    final consumedText = subInfo.consumption.sizeGB();
    final totalLabel = isInfinite ? "/ ∞ GiB" : "/ ${subInfo.total.sizeGB()}";
    final percentUsed = (subInfo.ratio * 100).toStringAsFixed(1);
    final daysLeft = subInfo.remaining.inDays;
    final isExpired = subInfo.isExpired;

    const accent = AppTheme.brandAccent;

    return Card(
      margin: EdgeInsets.zero,
      shadowColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.components.subscriptionInfo.monthlyQuota.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(color: accent, letterSpacing: 1.5),
            ),
            const Gap(8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  consumedText,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w400),
                ),
                const Gap(4),
                Flexible(
                  child: Text(
                    totalLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(color: accent, fontStyle: FontStyle.italic),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Gap(10),
            LinearProgressIndicator(
              value: subInfo.ratio,
              borderRadius: BorderRadius.circular(16),
              minHeight: 4,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.15),
            ),
            const Gap(10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t.components.subscriptionInfo.percentUsed(percent: percentUsed),
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  isExpired
                      ? t.components.subscriptionInfo.expired
                      : t.components.subscriptionInfo.daysLeft(days: daysLeft),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isExpired ? theme.colorScheme.error : accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
