import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The connection, at the foot of the sidebar: a dot and one word, then the
/// live speeds and the session total while connected. Reads the providers and
/// hands the words to [SidebarStatusView].
///
/// This replaced two cards, "Protected / Your connection is secure" over a
/// "Live traffic" panel with a green up arrow and a red down arrow. The
/// subtitle told the user what the word above it had just said; the arrows
/// coloured a download like an error. A status line is a line.
class SidebarStatus extends ConsumerWidget {
  const SidebarStatus({super.key, required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final protected = ref.watch(connectionNotifierProvider.select((value) => value.valueOrNull is Connected));
    final stats = protected ? ref.watch(statsNotifierProvider).asData?.value : null;

    return SidebarStatusView(
      extended: extended,
      protected: protected,
      label: protected ? t.connection.protected : t.connection.unprotected,
      upload: stats?.uplink.toInt().speed(),
      download: stats?.downlink.toInt().speed(),
      totalLabel: t.components.stats.trafficTotal,
      total: stats?.downlinkTotal.toInt().size(),
    );
  }
}

/// The footer itself, with the words already chosen. Extended: dot, label,
/// then the traffic lines when there are any. Collapsed: the dot alone,
/// carrying the label for hover and assistive technology, so the tablet rail
/// still says whether the tunnel is up.
class SidebarStatusView extends StatelessWidget {
  const SidebarStatusView({
    super.key,
    required this.extended,
    required this.protected,
    required this.label,
    required this.totalLabel,
    this.upload,
    this.download,
    this.total,
  });

  final bool extended;
  final bool protected;
  final String label;
  final String totalLabel;
  final String? upload;
  final String? download;
  final String? total;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final dot = Semantics(
      label: label,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(shape: BoxShape.circle, color: protected ? palette.success : palette.danger),
      ),
    );

    if (!extended) {
      return Padding(
        padding: const EdgeInsets.only(top: RaynSpacing.md),
        child: Tooltip(
          message: label,
          child: Center(child: dot),
        ),
      );
    }

    final muted = RaynTypography.caption.copyWith(color: palette.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: palette.glassBorder),
          const SizedBox(height: RaynSpacing.md),
          Row(
            children: [
              ExcludeSemantics(child: dot),
              const SizedBox(width: RaynSpacing.sm),
              Text(label, style: RaynTypography.label.copyWith(color: palette.textPrimary)),
            ],
          ),
          if (upload != null && download != null) ...[
            const SizedBox(height: RaynSpacing.xs),
            Row(
              children: [
                Icon(Icons.arrow_upward_rounded, size: 14, color: palette.textMuted),
                const SizedBox(width: RaynSpacing.xs),
                Text(upload!, style: muted),
                const SizedBox(width: RaynSpacing.md),
                Icon(Icons.arrow_downward_rounded, size: 14, color: palette.textMuted),
                const SizedBox(width: RaynSpacing.xs),
                Text(download!, style: muted),
              ],
            ),
          ],
          if (total != null) ...[const SizedBox(height: RaynSpacing.xs), Text('$totalLabel $total', style: muted)],
        ],
      ),
    );
  }
}
