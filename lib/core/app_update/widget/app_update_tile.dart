import 'package:flutter/material.dart';
import 'package:hiddify/core/app_update/app_update_checker.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The About page's update row, in the Windows EXE build only.
///
/// - A release is waiting: "Update to 1.6.2", which opens the dialog.
/// - Connected: "Check for updates", which asks the host now.
/// - Not connected: the account page, where the installer can always be
///   downloaded. Checks go only through the tunnel, so this is the way out
///   for a client that cannot connect at all.
class AppUpdateTile extends ConsumerWidget {
  const AppUpdateTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final copy = t.pages.about.update;
    final status = ref.watch(appUpdateCheckerProvider);
    final connected = ref.watch(connectionNotifierProvider.select((v) => v.valueOrNull?.isConnected ?? false));
    final offer = status.offer;

    if (offer != null) {
      return RaynSettingsTile(
        leading: Icons.system_update_alt_rounded,
        title: copy.available(version: offer.version),
        onTap: () => ref.read(appUpdateCheckerProvider.notifier).showOffer(),
      );
    }
    if (connected) {
      return RaynSettingsTile(
        leading: Icons.system_update_alt_rounded,
        title: copy.check,
        subtitle: status.checking ? copy.checking : null,
        enabled: !status.checking,
        onTap: status.checking
            ? null
            : () async {
                final outcome = await ref.read(appUpdateCheckerProvider.notifier).checkNow();
                final toasts = ref.read(inAppNotificationControllerProvider);
                switch (outcome) {
                  case AppUpdateOutcome.upToDate:
                    toasts.showSuccessToast(copy.upToDate);
                  case AppUpdateOutcome.failed || AppUpdateOutcome.refused:
                    toasts.showErrorToast(copy.failed);
                  case AppUpdateOutcome.offered || AppUpdateOutcome.notDue:
                    break;
                }
              },
      );
    }
    return RaynSettingsTile(
      leading: Icons.system_update_alt_rounded,
      title: copy.website,
      subtitle: copy.websiteSubtitle,
      trailing: const Icon(Icons.open_in_new_rounded),
      onTap: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
    );
  }
}
