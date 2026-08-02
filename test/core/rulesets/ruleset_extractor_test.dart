import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/rulesets/ruleset_extractor.dart';
import 'package:hiddify/core/rulesets/ruleset_manifest.dart';
import 'package:path/path.dart' as p;

/// These cover [RulesetExtractor.allFilesMatch] only — the gate that decides
/// whether the bundled rule-sets need re-extracting. The extraction itself reads
/// `rootBundle`, which needs asset mocking and is not what regressed.
///
/// The behaviour under test replaced a bare `File.exists()` check. A corrupted
/// `.srs` used to pass that check forever, because the version marker had
/// already been written, and the only symptom was the core refusing to start.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ruleset_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes [content] as `<tempDir>/<name>` and returns a manifest entry whose
  /// digest matches it.
  Future<RulesetManifestFile> writeFile(String name, List<int> content) async {
    await File(p.join(tempDir.path, name)).writeAsBytes(content, flush: true);
    return RulesetManifestFile(name: name, sha256: sha256.convert(content).toString());
  }

  RulesetManifest manifestOf(List<RulesetManifestFile> files) => RulesetManifest(version: "2026-07-24", files: files);

  group("allFilesMatch", () {
    test("accepts files whose digests match the manifest", () async {
      final manifest = manifestOf([
        await writeFile("direct-private.srs", [1, 2, 3]),
        await writeFile("direct-apple.srs", [4, 5, 6]),
      ]);

      expect(await RulesetExtractor.allFilesMatch(tempDir, manifest), isTrue);
    });

    test("accepts an empty manifest", () async {
      expect(await RulesetExtractor.allFilesMatch(tempDir, manifestOf([])), isTrue);
    });

    test("rejects a missing file", () async {
      final present = await writeFile("direct-private.srs", [1, 2, 3]);
      final manifest = manifestOf([
        present,
        const RulesetManifestFile(
          name: "direct-apple.srs",
          sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
      ]);

      expect(await RulesetExtractor.allFilesMatch(tempDir, manifest), isFalse);
    });

    // The regression this change exists for: a file of the right name, present
    // on disk, whose contents are wrong. The old existence check passed it.
    test("rejects a file whose contents were corrupted after extraction", () async {
      final entry = await writeFile("direct-regional-sites.srs", [1, 2, 3, 4]);
      await File(p.join(tempDir.path, entry.name)).writeAsBytes([9, 9, 9, 9], flush: true);

      expect(await RulesetExtractor.allFilesMatch(tempDir, manifestOf([entry])), isFalse);
    });

    // Truncation is the realistic corruption mode — an extract interrupted
    // mid-write, or a partial restore. It is a strict prefix, so any check
    // weaker than a digest (size aside) would let it through.
    test("rejects a truncated file", () async {
      final entry = await writeFile("direct-regional-ips.srs", [1, 2, 3, 4, 5, 6, 7, 8]);
      await File(p.join(tempDir.path, entry.name)).writeAsBytes([1, 2, 3, 4], flush: true);

      expect(await RulesetExtractor.allFilesMatch(tempDir, manifestOf([entry])), isFalse);
    });

    test("rejects an empty file where content was expected", () async {
      final entry = await writeFile("direct-apple.srs", [1, 2, 3]);
      await File(p.join(tempDir.path, entry.name)).writeAsBytes([], flush: true);

      expect(await RulesetExtractor.allFilesMatch(tempDir, manifestOf([entry])), isFalse);
    });

    test("accepts an uppercase digest in the manifest", () async {
      final entry = await writeFile("direct-private.srs", [1, 2, 3]);
      final upper = RulesetManifestFile(name: entry.name, sha256: entry.sha256.toUpperCase());

      expect(await RulesetExtractor.allFilesMatch(tempDir, manifestOf([upper])), isTrue);
    });

    test("rejects when the target directory does not exist", () async {
      final missing = Directory(p.join(tempDir.path, "nope"));
      final manifest = manifestOf([
        const RulesetManifestFile(
          name: "direct-private.srs",
          sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ),
      ]);

      expect(await RulesetExtractor.allFilesMatch(missing, manifest), isFalse);
    });
  });

  group("RulesetManifestFile", () {
    test("parses name and sha256, ignoring the unmodelled size field", () {
      final file = RulesetManifestFile.fromJson(const {
        "name": "direct-private.srs",
        "sha256": "260491243e0266e5ba543f509ca7f13b07d6f4c2c26ade3f675ddea1661f3213",
        "size": 754,
      });

      expect(file.name, "direct-private.srs");
      expect(file.sha256, "260491243e0266e5ba543f509ca7f13b07d6f4c2c26ade3f675ddea1661f3213");
    });

    // sha256 is required precisely so a manifest that omits it fails loudly
    // rather than silently downgrading the check back to "the file exists".
    test("throws when sha256 is absent", () {
      expect(
        () => RulesetManifestFile.fromJson(const {"name": "direct-private.srs", "size": 754}),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
