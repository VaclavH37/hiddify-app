import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_dialog_action.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';
import 'package:hiddify/features/connection/local_routing/model/egress_routing.dart';
import 'package:hiddify/features/connection/local_routing/model/local_routing_tracker.dart';
import 'package:hiddify/features/connection/local_routing/notifier/local_routing_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Home-page warning: the tunnel carries nothing because IP routing is on for
/// the adapter Windows sends Rayn's own connections out of.
///
/// Laid out like `NotificationBanner` and shown in its place, never under it.
/// Deliberately not a notification-inbox row: an older build reading an
/// unknown kind from the inbox would crash after a downgrade.
class LocalRoutingBanner extends ConsumerWidget {
  const LocalRoutingBanner({super.key, required this.issue});

  final LocalRoutingIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final adapter = issue.routing.alias;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: RaynSurface(
        elevated: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 24, color: palette.danger),
            const SizedBox(width: RaynSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.connection.localRouting.title,
                    style: RaynTypography.body.copyWith(color: palette.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.connection.localRouting.body(adapter: adapter),
                    style: RaynTypography.caption.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: RaynSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.sm),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => showLocalRoutingHelp(context, issue.routing),
                      child: Text(t.connection.localRouting.howToFix),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: RaynSpacing.sm),
            IconButton(
              onPressed: () => ref.read(localRoutingNotifierProvider.notifier).dismiss(),
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

/// The fix: remove the cause first (it survives a restart; the command does
/// not survive the service that set it), then the one-line command.
Future<void> showLocalRoutingHelp(BuildContext context, EgressRouting routing) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => LocalRoutingHelpDialog(routing: routing),
  );
}

class LocalRoutingHelpDialog extends ConsumerWidget {
  const LocalRoutingHelpDialog({super.key, required this.routing});

  final EgressRouting routing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final copy = t.connection.localRouting;
    final adapter = routing.alias;
    final paragraph = RaynTypography.caption.copyWith(color: palette.textSecondary, fontSize: 13, height: 1.4);

    Widget step(int number, String text) => Padding(
      padding: const EdgeInsets.only(top: RaynSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 20, child: Text('$number.', style: paragraph)),
          Expanded(child: Text(text, style: paragraph)),
        ],
      ),
    );

    Future<void> copyCommand() async {
      await Clipboard.setData(ClipboardData(text: routing.fixCommand));
      ref.read(inAppNotificationControllerProvider).showSuccessToast(copy.copied);
    }

    return AlertDialog.adaptive(
      title: Text(copy.dialogTitle(adapter: adapter)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(copy.intro(adapter: adapter), style: paragraph),
              step(1, copy.stepSharing(adapter: adapter)),
              step(2, copy.stepIncoming),
              step(3, copy.commandIntro),
              const SizedBox(height: RaynSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(RaynSpacing.md, RaynSpacing.sm, RaynSpacing.xs, RaynSpacing.sm),
                decoration: BoxDecoration(
                  color: palette.groupFill,
                  borderRadius: BorderRadius.circular(RaynRadius.control),
                  border: Border.all(color: palette.hairline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        routing.fixCommand,
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: palette.textPrimary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: copyCommand,
                      icon: const Icon(Icons.content_copy_rounded, size: 16),
                      label: Text(copy.copy),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: RaynSpacing.md),
              Text(copy.footer, style: paragraph),
            ],
          ),
        ),
      ),
      actions: [raynDialogAction(context, label: t.common.close, onPressed: () => Navigator.of(context).pop())],
    );
  }
}
