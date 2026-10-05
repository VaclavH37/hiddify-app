import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_update/update_install.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:path/path.dart' as p;

/// The installer step of the Windows updater: where the file goes, the check
/// that runs right before launching it, how the installer is started, and how
/// the next launch tells a finished update from one that did not install.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('rayn_update_install_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  final bytes = List<int>.generate(70000, (i) => (i * 13) % 256);
  UpdateInstaller installer({int? size, String? digest}) => UpdateInstaller(
    path: 'app/windows/RaynVPN-1.6.2-10602-windows.exe',
    size: size ?? bytes.length,
    sha256: digest ?? sha256.convert(bytes).toString(),
  );

  test('downloads go to updates\\ beside the executable, under the manifest file name', () {
    final exe = p.join('C:', 'Program Files', 'RaynVPN', 'RaynVPN.exe');
    expect(updatesDirectory(exe).path, p.join('C:', 'Program Files', 'RaynVPN', 'updates'));
    expect(installerFileName(installer()), 'RaynVPN-1.6.2-10602-windows.exe');
  });

  group('installerProblem', () {
    late File file;
    setUp(() => file = File(p.join(dir.path, 'setup.exe'))..writeAsBytesSync(bytes));

    test('the file the signed manifest describes passes', () async {
      expect(await installerProblem(file, installer()), isNull);
    });

    test('a different size fails before the digest is read', () async {
      expect(await installerProblem(file, installer(size: bytes.length + 1)), contains('bytes'));
    });

    test('the right size with other content fails', () async {
      file.writeAsBytesSync([...bytes.sublist(0, bytes.length - 1), bytes.last ^ 0xff]);
      expect(await installerProblem(file, installer()), 'does not match its digest');
    });
  });

  test('the installer runs silently and is told to start the new build, reconnecting only if asked', () {
    expect(installerArguments(reconnect: true, logPath: r'C:\Program Files\RaynVPN\updates\install.log'), [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/RAYNUPDATE=1',
      '/RAYNRECONNECT=1',
      r'/LOG=C:\Program Files\RaynVPN\updates\install.log',
    ]);
    expect(installerArguments(reconnect: false, logPath: 'x'), contains('/RAYNRECONNECT=0'));
  });

  test('clearing the folder removes installers and partial downloads but keeps the log', () {
    for (final name in ['RaynVPN-1.6.2-10602-windows.exe', 'RaynVPN-1.6.3-10603-windows.exe.part', updateLogName]) {
      File(p.join(dir.path, name)).writeAsStringSync('x');
    }
    expect(clearUpdatesFolder(dir), 0);
    expect(dir.listSync().map((e) => p.basename(e.path)), [updateLogName]);
    expect(clearUpdatesFolder(Directory(p.join(dir.path, 'missing'))), 0);
  });

  test('a file still in use is left for later and counted', () {
    final busy = File(p.join(dir.path, 'RaynVPN-1.6.2-10602-windows.exe'))..writeAsStringSync('x');
    final handle = busy.openSync(mode: FileMode.append);
    addTearDown(handle.closeSync);
    // Windows refuses to delete an open file; elsewhere the delete succeeds.
    expect(clearUpdatesFolder(dir), Platform.isWindows ? 1 : 0);
  });

  test("the installer's switches are read from the command line", () {
    final both = UpdateLaunch.parse(['--updated', '--reconnect']);
    expect((both.updated, both.reconnect), (true, true));
    final plain = UpdateLaunch.parse(const []);
    expect((plain.updated, plain.reconnect), (false, false));
  });

  group('settleUpdateAttempt', () {
    test('the build the update was installing has started: installed', () {
      expect(
        settleUpdateAttempt(attemptBuild: 10602, currentBuild: 10602, updated: true),
        UpdateAttemptOutcome.installed,
      );
      expect(
        settleUpdateAttempt(attemptBuild: 10602, currentBuild: 10603, updated: false),
        UpdateAttemptOutcome.installed,
        reason: 'started by hand later, or a newer build came first',
      );
    });

    test('the old build has started again: the install did not finish', () {
      expect(
        settleUpdateAttempt(attemptBuild: 10602, currentBuild: 10601, updated: false),
        UpdateAttemptOutcome.notInstalled,
      );
    });

    test("no attempt on record: only the installer's flag says it was an update", () {
      expect(settleUpdateAttempt(currentBuild: 10602, updated: true), UpdateAttemptOutcome.installed);
      expect(settleUpdateAttempt(currentBuild: 10602, updated: false), UpdateAttemptOutcome.none);
    });
  });
}
