import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/logger/logger.dart';
import 'package:loggy/loggy.dart';

/// Flutter's own errors (building, layout, painting) reach the log through
/// FlutterError.onError, which bootstrap.dart points at [Logger.logFlutterError].
/// Assigning it replaced the full report with one terse line (upstream
/// 676a8904): a crash said what was thrown, not where.
void main() {
  late List<LogRecord> logged;
  late List<FlutterErrorDetails> presented;

  setUp(() {
    logged = [];
    Loggy.initLoggy(logPrinter: _Capture(logged));
    presented = [];
    final present = FlutterError.presentError;
    FlutterError.presentError = presented.add;
    addTearDown(() => FlutterError.presentError = present);
  });

  FlutterErrorDetails details({bool silent = false}) => FlutterErrorDetails(
    exception: StateError('no size'),
    stack: StackTrace.current,
    library: 'rendering library',
    context: ErrorDescription('during performLayout()'),
    silent: silent,
  );

  test('the log line says which part of Flutter failed and what it was doing', () {
    Logger.logFlutterError(details());

    expect(logged.single.level, LogLevel.error);
    expect(logged.single.message, 'Flutter error in rendering library during performLayout(): Bad state: no size');
    expect(logged.single.error, isA<StateError>());
    expect(logged.single.stackTrace, isNotNull);
  });

  test('a debug build still prints the full report', () {
    final error = details();
    Logger.logFlutterError(error);
    expect(presented, [same(error)]);
  }, skip: kDebugMode ? false : 'debug builds only');

  test('an error without a context still logs, under the default library', () {
    Logger.logFlutterError(FlutterErrorDetails(exception: StateError('no size')));
    expect(logged.single.message, 'Flutter error in Flutter framework: Bad state: no size');
  });

  test('a silent error is not logged', () {
    Logger.logFlutterError(details(silent: true));
    expect(logged, isEmpty);
  });
}

class _Capture extends LoggyPrinter {
  _Capture(this.records);

  final List<LogRecord> records;

  @override
  void onLog(LogRecord record) => records.add(record);
}
