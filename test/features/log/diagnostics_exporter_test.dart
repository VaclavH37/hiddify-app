import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/log/data/diagnostics_exporter.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory workingDir;

  setUp(() {
    workingDir = Directory.systemTemp.createTempSync('rayn-diagnostics-test');
    Directory(p.join(workingDir.path, 'data')).createSync();
  });

  tearDown(() {
    if (workingDir.existsSync()) workingDir.deleteSync(recursive: true);
  });

  void write(String relative, String contents) {
    final file = File(p.joinAll([workingDir.path, ...p.posix.split(relative)]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  List<String> collectedNames() =>
      DiagnosticsExporter(workingDir).collect().map((f) => p.basename(f.path)).toList();

  group('DiagnosticsExporter', () {
    test('returns nothing when the working directory is empty', () {
      expect(DiagnosticsExporter(workingDir).collect(), isEmpty);
    });

    test('collects only the logs that exist', () {
      write('data/stderr4.log', 'background core');
      write('app.log', 'loggy');

      expect(collectedNames(), ['stderr4.log', 'app.log']);
    });

    test('orders results most-useful-first, not by discovery', () {
      // Written in reverse of the declared order to prove the order is the
      // allowlist's, not the filesystem's.
      write('data/box.log', 'core file');
      write('app.log', 'loggy');
      write('data/stderr3.log', 'foreground core');
      write('data/stderr4.log', 'background core');
      write('network_extension_error.log', 'extension lifecycle');

      expect(collectedNames(), [
        // The Swift-written file first: it survives the core failing to start at
        // all, which is the case you most need it for.
        'network_extension_error.log',
        'stderr4.log',
        'stderr3.log',
        'app.log',
        'box.log',
      ]);
    });

    test('skips empty files', () {
      // A zero-byte log in a share sheet is worse than an absent one, because it
      // looks like an answer.
      write('data/stderr4.log', '');
      write('data/stderr3.log', 'foreground core');

      expect(collectedNames(), ['stderr3.log']);
    });

    // The security-relevant one. The working directory also holds the sealed
    // config, the extracted rule-sets and the core's LevelDB. Sealing the config
    // at rest exists to keep the hub IP, the per-user UUIDs and the Reality
    // shortIDs off disk in plaintext; sweeping any of it into a share sheet would
    // undo that from the other end.
    test('never collects anything outside the allowlist', () {
      write('configs/6f9619ff-8b86-d011-b42d-00c04fc964ff.enc', 'sealed config');
      write('configs/current-config.json', '{"outbounds":[]}');
      write('rulesets/direct-private.srs', 'ruleset');
      write('rulesets/MANIFEST', 'manifest');
      write('data/clash.db', 'leveldb');
      write('data/debug-built-config.json', '{"inbounds":[]}');
      write('data/stderr4.log', 'background core');
      // Same suffix as a real log, adjacent to one, and still not ours.
      write('data/some-other.log', 'not in the allowlist');
      write('secrets.log', 'not in the allowlist either');

      expect(collectedNames(), ['stderr4.log']);
    });

    test('the allowlist itself contains no config, ruleset or database paths', () {
      // Guards the list rather than the traversal: a future addition of
      // `data/debug-built-config.json` "just for debugging" would pass every test
      // above, because it really would be collected.
      for (final entry in DiagnosticsExporter.logFiles) {
        expect(
          entry.endsWith('.log'),
          isTrue,
          reason: '"$entry" is not a .log file — the exporter shares files to a '
              'destination the user chooses, so only logs belong in this list.',
        );
        expect(
          entry,
          isNot(anyOf(contains('config'), contains('ruleset'), contains('.db'))),
          reason: '"$entry" looks like config, rule-set or database content.',
        );
      }
    });

    test('tolerates a missing working directory', () {
      final absent = Directory(p.join(workingDir.path, 'does-not-exist'));
      expect(DiagnosticsExporter(absent).collect(), isEmpty);
    });
  });
}
