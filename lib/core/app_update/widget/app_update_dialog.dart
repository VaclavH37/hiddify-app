import 'package:flutter/material.dart';
import 'package:hiddify/core/app_update/app_update_checker.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How the dialog was closed without installing.
enum AppUpdateChoice { later, skip }

/// Offers a newer Windows release and, after Install, shows the install.
///
/// The offer: its version and size, what installing does to the connection,
/// and the choice. Nothing is downloaded before the user picks Install: the
/// installer is about 33 MB, and it counts against their quota because it
/// comes through the tunnel. For the same reason Install needs a connection.
/// Nothing takes the focus, so Enter does not start a download.
///
/// An important release drops "Skip this version" and says why it matters. It
/// still never blocks connecting.
///
/// After Install the dialog stays: download progress with Cancel, then the
/// check against the signed manifest, then "Installing" while the app closes.
/// It cannot be dismissed until it is done or has failed.
class AppUpdateDialog extends ConsumerWidget {
  const AppUpdateDialog({super.key, required this.offer});

  final UpdateManifest offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final copy = t.dialogs.appUpdate;
    final connected = ref.watch(connectionNotifierProvider.select((v) => v.valueOrNull?.isConnected ?? false));
    final status = ref.watch(appUpdateCheckerProvider);
    final checker = ref.read(appUpdateCheckerProvider.notifier);
    final secondary = RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: palette.textSecondary);

    void close([AppUpdateChoice choice = AppUpdateChoice.later]) => Navigator.of(context).pop(choice);

    final (Widget body, List<Widget> actions) = switch (status.progress) {
      null => (
        Column(
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
            Text(connected ? copy.whatHappens : copy.connectFirst, style: secondary),
          ],
        ),
        [
          if (!offer.important) TextButton(onPressed: () => close(AppUpdateChoice.skip), child: Text(copy.skip)),
          TextButton(onPressed: close, child: Text(copy.later)),
          FilledButton(onPressed: connected ? () => checker.install(offer) : null, child: Text(copy.install)),
        ],
      ),
      UpdateDownloading(:final received, :final total) => (
        _Progress(
          label: copy.downloading(received: '${received >> 20}', total: '${appUpdateMegabytes(total)}'),
          value: total > 0 ? received / total : null,
        ),
        [TextButton(onPressed: checker.cancelDownload, child: Text(t.common.cancel))],
      ),
      UpdateVerifying() => (_Progress(label: copy.verifying), const <Widget>[]),
      UpdateInstalling() => (_Progress(label: copy.installing), const <Widget>[]),
      UpdateFailed(:final reason) => (
        Text(switch (reason) {
          UpdateFailure.download => copy.failedDownload,
          UpdateFailure.damaged => copy.failedDamaged,
          UpdateFailure.launch => copy.failedLaunch,
        }),
        [
          if (reason == UpdateFailure.launch)
            TextButton(
              onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
              child: Text(copy.openAccount),
            ),
          TextButton(onPressed: close, child: Text(t.common.close)),
        ],
      ),
    };

    return PopScope(
      canPop: !status.busy,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.xl, RaynSpacing.xl, 0),
        contentPadding: EdgeInsets.fromLTRB(
          RaynSpacing.xl,
          RaynSpacing.md,
          RaynSpacing.xl,
          actions.isEmpty ? RaynSpacing.xl : 0,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(RaynSpacing.lg, RaynSpacing.lg, RaynSpacing.lg, RaynSpacing.lg),
        title: Text(copy.title),
        content: ConstrainedBox(constraints: const BoxConstraints(minWidth: 280, maxWidth: 400), child: body),
        actions: actions.isEmpty ? null : actions,
      ),
    );
  }
}

/// A line of what is happening over a bar: determinate while downloading,
/// indeterminate otherwise.
class _Progress extends StatelessWidget {
  const _Progress({required this.label, this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: RaynSpacing.md),
      LinearProgressIndicator(value: value),
    ],
  );
}
