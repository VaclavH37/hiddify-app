import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';

class Logger {
  static final app = Loggy("app");
  static final bootstrap = Loggy("bootstrap");

  static void logFlutterError(FlutterErrorDetails details) {
    // Assigning this handler to FlutterError.onError (bootstrap.dart) replaced
    // its default, presentError, which prints the full report: the widget that
    // failed and what it was doing. Debug builds keep that report. It leaves
    // out a silent error itself.
    if (kDebugMode) FlutterError.presentError(details);

    if (details.silent) {
      return;
    }

    // library and context are what exceptionAsString() leaves out: which part
    // of Flutter failed ("widgets library") and what it was doing ("while
    // building ..."), the two that say where to look.
    final library = details.library ?? 'unknown library';
    final context = details.context == null ? '' : ' ${details.context}';
    app.error('Flutter error in $library$context: ${details.exceptionAsString()}', details.exception, details.stack);
  }

  static bool logPlatformDispatcherError(Object error, StackTrace stackTrace) {
    app.error('PlatformDispatcherError: $error', error, stackTrace);
    return true;
  }
}
