import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/log/data/diagnostics_exporter.dart';
import 'package:hiddify/utils/alerts.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Hand the log files to the platform share sheet.
///
/// Extracted so Settings and the auth wall share one implementation rather than
/// two copies of the clipboard fallback below, which is subtle enough that a
/// divergent copy would be a bug waiting to happen.
Future<void> exportDiagnostics(BuildContext context, WidgetRef ref, Translations t) async {
  final exporter = DiagnosticsExporter(
    ref.read(appDirectoriesProvider).requireValue.workingDir,
  );
  final files = exporter.collect();
  if (files.isEmpty) {
    if (context.mounted) {
      CustomToast(t.pages.settings.exportDiagnosticsEmpty).show(context);
    }
    return;
  }
  try {
    await Share.shareXFiles([
      for (final file in files) XFile(file.path, mimeType: "text/plain"),
    ]);
  } catch (e) {
    // Fall back to the clipboard rather than dead-ending. The share sheet goes
    // through a native plugin and a UIActivityViewController; when that throws
    // there is nothing to debug from Dart and, on iOS, no second route off the
    // device. Observed failing on a real device.
    //
    // Report by kind, never by value — a platform exception can carry absolute
    // paths, and this is a screen the user may screenshot.
    await Clipboard.setData(ClipboardData(text: exporter.asText()));
    if (context.mounted) {
      CustomToast(t.pages.settings.exportDiagnosticsCopied).show(context);
    }
  }
}
