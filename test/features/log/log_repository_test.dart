import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/log/data/log_path_resolver.dart';
import 'package:hiddify/features/log/data/log_repository.dart';
import 'package:hiddify/hiddifycore/rayn_core_service.dart';

class _UnusedCore extends Fake implements RaynCoreService {}

/// The app's file logger opens app.log at bootstrap and writes through a sink
/// that keeps its own offset. Emptying the file under it afterwards turned
/// everything logged before the log repository started into NUL bytes at the
/// top of app.log (2026-10-19, Android and Windows).
void main() {
  late Directory workingDir;
  late LogPathResolver paths;

  setUp(() {
    workingDir = Directory.systemTemp.createTempSync('rayn-log-repository-test');
    paths = LogPathResolver(workingDir);
  });

  tearDown(() {
    if (workingDir.existsSync()) workingDir.deleteSync(recursive: true);
  });

  Future<void> init() async {
    final result = await LogRepositoryImpl(singbox: _UnusedCore(), logPathResolver: paths).init().run();
    expect(result.isRight(), isTrue);
  }

  test('init leaves app.log to the logger already writing it', () async {
    // The same mode FileLogPrinter opens it with.
    final sink = paths.appFile().openWrite(mode: FileMode.writeOnly);
    sink.writeln('bootstrap: initializing [rule-sets]');
    await sink.flush();

    await init();

    sink.writeln('bootstrap: [logs repository] initialized');
    await sink.close();

    final bytes = paths.appFile().readAsBytesSync();
    expect(bytes, isNot(contains(0)), reason: 'app.log must not start with NUL bytes');
    expect(utf8.decode(bytes), 'bootstrap: initializing [rule-sets]\nbootstrap: [logs repository] initialized\n');
  });

  test("init still empties the core's box.log", () async {
    paths.coreFile().writeAsStringSync('last session');
    await init();
    expect(paths.coreFile().readAsStringSync(), isEmpty);
  });
}
