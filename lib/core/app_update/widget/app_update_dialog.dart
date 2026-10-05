import 'package:flutter/material.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum AppUpdateChoice { install, later, skip }

/// Offers a newer Windows release: its version and size, what installing does
/// to the connection, and the choice.
///
/// Nothing is downloaded before the user picks Install: the installer is
/// about 33 MB, and it counts against their quota because it comes through
/// the tunnel. For the same reason Install needs a connection. Nothing takes
/// the focus, so Enter does not start a download.
///
/// An important release drops "Skip this version" and says why it matters. It
/// still never blocks connecting.
class AppUpdateDialog extends ConsumerWidget {
  const AppUpdateDialog({super.key, required this.offer});

  final UpdateManifest offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final copy = t.dialogs.appUpdate;
    final connected = ref.watch(connectionNotifierProvider.select((v) => v.valueOrNull?.isConnected ?? false));

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.xl, RaynSpacing.xl, 0),
      contentPadding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.md, RaynSpacing.xl, 0),
      actionsPadding: const EdgeInsets.fromLTRB(RaynSpacing.lg, RaynSpacing.lg, RaynSpacing.lg, RaynSpacing.lg),
      title: Text(copy.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(copy.body(version: offer.version, size: '${appUpdateMegabytes(offer.installer.size)}')),
            if (offer.important) ...[
              const SizedBox(height: RaynSpacing.sm),
              Text(
                copy.important,
                style: RaynTypography.body.copyWith(fontWeight: FontWeight.w600, color: palette.textPrimary),
              ),
            ],
            const SizedBox(height: RaynSpacing.sm),
            Text(
              connected ? copy.whatHappens : copy.connectFirst,
              style: RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: palette.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        if (!offer.important)
          TextButton(onPressed: () => Navigator.of(context).pop(AppUpdateChoice.skip), child: Text(copy.skip)),
        TextButton(onPressed: () => Navigator.of(context).pop(AppUpdateChoice.later), child: Text(copy.later)),
        FilledButton(
          onPressed: connected ? () => Navigator.of(context).pop(AppUpdateChoice.install) : null,
          child: Text(copy.install),
        ),
      ],
    );
  }
}
