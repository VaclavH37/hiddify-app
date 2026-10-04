import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/rulesets/srs_check.dart';
import 'package:path/path.dart' as p;

/// A downloaded rule-set reaches the core only if this says it would load.
/// The core refuses a bad file at its next start, so anything this lets
/// through is a failed connect.
void main() {
  List<int> srs(List<int> body, {int version = 1}) => [0x53, 0x52, 0x53, version, ...zlib.encode(body)];

  final bundled = Directory(
    p.join('assets', 'rulesets'),
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.srs')).toList();

  test('every bundled rule-set passes', () {
    expect(bundled, isNotEmpty);
    for (final file in bundled) {
      expect(srsProblem(file.readAsBytesSync()), isNull, reason: p.basename(file.path));
    }
  });

  // dart:io's zlib decoder inflates a truncated stream without complaint,
  // which is why the check runs the Adler-32 itself.
  test('a truncated file fails its checksum', () {
    for (final file in bundled) {
      final bytes = file.readAsBytesSync();
      for (final cut in [bytes.length - 1, bytes.length ~/ 2]) {
        expect(srsProblem(bytes.sublist(0, cut)), isNotNull, reason: '${p.basename(file.path)} cut at $cut');
      }
    }
  });

  test('a flipped bit in the body is caught', () {
    final bytes = File(p.join('assets', 'rulesets', 'block-ads.srs')).readAsBytesSync();
    final damaged = [...bytes]..[bytes.length ~/ 2] ^= 0x01;
    expect(srsProblem(damaged), isNotNull);
  });

  test('a minimal well-formed file passes', () {
    expect(srsProblem(srs([1, 0])), isNull);
  });

  test('an error page is not a rule-set', () {
    expect(srsProblem('<html><body>502 Bad Gateway</body></html>'.codeUnits), 'not a rule-set file');
  });

  test('too few bytes is not a rule-set', () {
    expect(srsProblem([0x53, 0x52, 0x53, 1]), isNotNull);
  });

  test('a format newer than this core reads is refused', () {
    expect(srsProblem(srs([1, 0], version: kMaxSrsVersion + 1)), contains('format version ${kMaxSrsVersion + 1}'));
    expect(srsProblem(srs([1, 0], version: kMaxSrsVersion)), isNull);
  });

  test('version 0 is refused', () {
    expect(srsProblem(srs([1, 0], version: 0)), contains('format version 0'));
  });

  test('a body that is not zlib is refused', () {
    expect(srsProblem([0x53, 0x52, 0x53, 1, ...'<html></html>'.codeUnits]), isNotNull);
  });

  test('a body declaring no rules is refused', () {
    expect(srsProblem(srs([0])), 'body declares no rules');
  });

  // A few kilobytes that inflate to more than the cap: without it, a crafted
  // file could exhaust the tunnel extension's memory on iOS.
  test('a body that inflates past the cap is refused', () {
    final bomb = srs([1, ...List<int>.filled(srsInflatedCap, 0)]);
    expect(bomb.length, lessThan(100 * 1024));
    expect(srsProblem(bomb), contains('inflates past'));
  });
}
