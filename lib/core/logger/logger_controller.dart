import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hiddify/core/logger/custom_logger.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:loggy/loggy.dart';

class LoggerController extends LoggyPrinter with InfraLogger {
  LoggerController(this.consolePrinter, this.otherPrinters);

  final LoggyPrinter consolePrinter;
  final Map<String, LoggyPrinter> otherPrinters;

  static LoggerController get instance => _instance;

  static late LoggerController _instance;

  static void preInit() {
    Loggy.initLoggy(logPrinter: const ConsolePrinter());
  }

  static void init(String appLogPath) {
    _instance = LoggerController(const ConsolePrinter(), {
      "app": kIsWeb ? const ConsolePrinter() : FileLogPrinter(appLogPath),
    });
    Loggy.initLoggy(logPrinter: _instance);
  }

  /// [debugMode] is `Constants.diagnosticsBuild` — one gate covering the log
  /// level, the log file and the export button, so a build can never offer to
  /// share logs it was not writing.
  ///
  /// A diagnostics build logs everything. It used to read `debugMode && false`,
  /// which pinned every build to `info` and silently discarded every
  /// `loggy.debug` call in the app — including the ones that explain what the
  /// hub-reachability ladder decided and why, which are exactly what a
  /// diagnostics build exists to capture.
  ///
  /// Safe because nothing sensitive is logged at debug level: preference writes
  /// carry only toggles and counters, subscription failures are reported by
  /// reason rather than by value, and hosts are logged without their paths or
  /// tokens. Keep it that way — this level now reaches a share sheet.
  static Future<void> postInit(bool debugMode) async {
    final logLevel = debugMode ? LogLevel.all : LogLevel.info;
    final logToFile = debugMode || (!Platform.isAndroid && !Platform.isIOS);

    if (!logToFile || kIsWeb) _instance.removePrinter("app");

    Loggy.initLoggy(logPrinter: _instance, logOptions: LogOptions(logLevel));
  }

  void addPrinter(String name, LoggyPrinter printer) {
    loggy.debug("adding [$name] printer");
    otherPrinters.putIfAbsent(name, () => printer);
  }

  void removePrinter(String name) {
    loggy.debug("removing [$name] printer");
    final printer = otherPrinters[name];
    if (printer case FileLogPrinter()) {
      printer.dispose();
    }
    otherPrinters.remove(name);
  }

  @override
  void onLog(LogRecord record) {
    consolePrinter.onLog(record);
    for (final printer in otherPrinters.values) {
      printer.onLog(record);
    }
  }
}
