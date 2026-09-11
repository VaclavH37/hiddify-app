import 'package:flutter/services.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/log/data/diagnostics_exporter.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hand the log files to the platform share sheet.
///
/// Extracted so Settings and the auth wall share one implementation rather than
/// two copies of the clipboard fallback below, which is subtle enough that a
/// divergent copy would be a bug waiting to happen. Both callers are gated on
/// `Constants.diagnosticsBuild`, the switch that also decides whether any log
/// is written, so the "no logs yet" case below is a fresh diagnostics build
/// that has not connected, never a production build that cannot log.
Future<void> exportDiagnostics(WidgetRef ref, Translations t) async {
  final notifications = ref.read(inAppNotificationControllerProvider);
  final exporter = DiagnosticsExporter(ref.read(appDirectoriesProvider).requireValue.workingDir);
  final files = exporter.collect();
  if (files.isEmpty) {
    notifications.showInfoToast(t.pages.settings.exportDiagnosticsEmpty);
    return;
  }
  try {
    await Share.shareXFiles([for (final file in files) XFile(file.path, mimeType: "text/plain")]);
  } catch (e) {
    // Fall back to the clipboard rather than dead-ending. The share sheet goes
    // through a native plugin and a UIActivityViewController; when that throws
    // there is nothing to debug from Dart and, on iOS, no second route off the
    // device. Observed failing on a real device.
    //
    // Report by kind, never by value — a platform exception can carry absolute
    // paths, and this is a screen the user may screenshot.
    await Clipboard.setData(ClipboardData(text: exporter.asText()));
    notifications.showInfoToast(t.pages.settings.exportDiagnosticsCopied);
  }
}
