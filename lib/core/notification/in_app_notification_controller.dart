import 'package:flutter/material.dart';
import 'package:hiddify/core/notification/rayn_toast.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:toastification/toastification.dart';

export 'package:hiddify/core/notification/rayn_toast.dart' show NotificationType;

part 'in_app_notification_controller.g.dart';

@Riverpod(keepAlive: true)
InAppNotificationController inAppNotificationController(Ref ref) {
  return InAppNotificationController();
}

/// Shows one toast at a time as a [RaynToast]. The library keeps the queue,
/// the auto-close timer, the overlay and swipe-to-dismiss; the widget, the
/// position and the motion come from `rayn_toast.dart`.
class InAppNotificationController with AppLogger {
  ToastificationItem _show(
    String message, {
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    toastification.dismissAll();
    return toastification.showCustom(
      // The app navigator's context resolves the theme, the text direction
      // and the toast configuration published above it in app.dart.
      context: rootNavKey.currentContext,
      autoCloseDuration: duration,
      dismissDirection: DismissDirection.horizontal,
      builder: (context, holder) => MouseRegion(
        onEnter: (_) => holder.pause(),
        onExit: (_) => holder.start(),
        child: RaynToast(type: type, message: message, onClose: () => toastification.dismiss(holder)),
      ),
    );
  }

  ToastificationItem? showErrorToast(String message) =>
      _show(message, type: NotificationType.error, duration: const Duration(seconds: 5));

  ToastificationItem? showSuccessToast(String message) => _show(message, type: NotificationType.success);

  ToastificationItem? showInfoToast(String message, {Duration duration = const Duration(seconds: 3)}) =>
      _show(message, duration: duration);
}
