import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';
import 'package:hiddify/features/connection/clock/data/date_time_settings.dart';
import 'package:hiddify/features/connection/clock/notifier/clock_skew_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Home-page warning: the device clock is far enough off that the hubs refuse
/// the connection.
///
/// Laid out like `LocalRoutingBanner` and shown in the same slot. Not a
/// notification-inbox row, for the same reason: it describes a condition that
/// holds now, and an older build reading an unknown inbox kind would crash after
/// a downgrade.
///
/// [canOpenSettings] and [apple] default to the running platform; tests set them.
class ClockBanner extends ConsumerWidget {
  const ClockBanner({super.key, this.canOpenSettings, this.apple});

  final bool? canOpenSettings;
  final bool? apple;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final copy = t.connection.clock;
    final openable = canOpenSettings ?? canOpenDateTimeSettings;
    final onApple = apple ?? Theme.of(context).platform == TargetPlatform.iOS;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: RaynSurface(
        elevated: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.schedule_rounded, size: 24, color: palette.warning),
            const SizedBox(width: RaynSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.title,
                    style: RaynTypography.body.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    onApple ? copy.bodyApple : copy.body,
                    style: RaynTypography.caption.copyWith(color: palette.textMuted),
                  ),
                  if (openable) ...[
                    const SizedBox(height: RaynSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.sm),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => unawaited(openDateTimeSettings()),
                        child: Text(copy.openSettings),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: RaynSpacing.sm),
            IconButton(
              onPressed: () => ref.read(clockSkewNotifierProvider.notifier).dismiss(),
              icon: Icon(Icons.close_rounded, size: 18, color: palette.textMuted),
              tooltip: t.notifications.dismiss,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            ),
          ],
        ),
      ),
    );
  }
}
