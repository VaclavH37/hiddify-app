@Tags(['design'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Executable versions of the decisions recorded in
/// `docs/upstream/DESIGN-INVARIANTS.md`.
///
/// These are deliberately unlike the rest of the suite: they assert on *source
/// and build files* rather than on behaviour. That is the point. Each one guards
/// a decision whose regression is silent — re-adding a dependency, restoring a
/// permission, dropping a build flag — and which every behavioural test in the
/// repo would happily stay green through. They exist because the upstream
/// catch-up will be applying commits from a codebase that made the opposite
/// choice in each case.
///
/// The Go-side counterparts live in `hiddify-core/v2/{config,hcore}`:
/// no FakeIP, no `experimental.debug` listener, no ungated `SaveCurrentConfig`
/// call, nothing serving `http.DefaultServeMux`.
void main() {
  group('Sentry stays removed', () {
    // Removed entirely, including the native crashpad checkouts under external/.
    // Upstream still ships it, so any merge that touches pubspec or bootstrap is
    // a chance for it to come back — and it would come back as ambient telemetry
    // from a VPN client, reporting on users who cannot see it happening.
    // DESIGN-INVARIANTS.md#no-sentry

    test('no sentry dependency in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final offenders = const ['sentry_flutter', 'sentry_dart_plugin', 'sentry:']
          .where(pubspec.contains)
          .toList();
      expect(
        offenders,
        isEmpty,
        reason: 'pubspec.yaml declares $offenders. Sentry was removed from this '
            'fork; see DESIGN-INVARIANTS.md#no-sentry.',
      );
    });

    test('no sentry package resolved in pubspec.lock', () {
      final lock = File('pubspec.lock').readAsStringSync();
      expect(
        RegExp(r'^\s{2}sentry\w*:', multiLine: true).hasMatch(lock),
        isFalse,
        reason: 'pubspec.lock resolves a sentry package, so something still '
            'depends on it transitively.',
      );
    });

    test('no sentry import anywhere in lib/', () {
      final offenders = _dartFilesUnder('lib')
          .where((f) => f.readAsStringSync().contains("package:sentry"))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: 'sentry imported by: $offenders');
    });
  });

  group('Play compliance', () {
    // QUERY_ALL_PACKAGES was dropped together with the per-app-proxy feature.
    // It is a sensitive permission that requires a declaration and blocks
    // release without one. Upstream still requests it for per-app proxy, so any
    // manifest change coming from upstream can silently reinstate it.
    // DESIGN-INVARIANTS.md#no-query-all-packages
    test('QUERY_ALL_PACKAGES is not requested in any manifest', () {
      for (final manifest in _filesNamed('android', 'AndroidManifest.xml')) {
        // Strip XML comments first: main/AndroidManifest.xml documents the
        // removal in prose, and a naive substring search would flag its own
        // explanation.
        final xml = manifest
            .readAsStringSync()
            .replaceAll(RegExp('<!--.*?-->', dotAll: true), '');
        expect(
          xml.contains('QUERY_ALL_PACKAGES'),
          isFalse,
          reason: '${manifest.path} requests QUERY_ALL_PACKAGES. It blocks Play '
              'release without a sensitive-permission declaration and was '
              'removed with per-app proxy.',
        );
      }
    });
  });

  group('shipped artifacts are obfuscated', () {
    // --obfuscate --split-debug-info is the layer that makes the masked
    // rayn:// key tables worth having. Losing it on one platform is invisible
    // until someone pulls the artifact apart.
    // DESIGN-INVARIANTS.md#obfuscate-shipped-artifacts
    //
    // Note obfuscation does NOT strip string literals — that is why key-path
    // logging is kDebugMode-gated separately.
    const leafReleaseTargets = [
      'android-apk-release',
      'android-aab-release',
      'windows-zip-release',
      'windows-exe-release',
      'windows-msix-release',
      'linux-deb-release',
      'linux-appimage-release',
      'macos-release',
      'ios-release',
    ];

    final makefile = File('Makefile').readAsStringSync();
    final recipes = _makeRecipes(makefile);

    test('FF_OBFUSCATE is defined and carries both flags', () {
      final definition = RegExp(r'^FF_OBFUSCATE\s*=\s*(.+)$', multiLine: true)
          .firstMatch(makefile)
          ?.group(1);
      expect(definition, isNotNull, reason: 'FF_OBFUSCATE is not defined in the Makefile');
      expect(definition, contains('obfuscate'));
      expect(definition, contains('split-debug-info'));
    });

    for (final target in leafReleaseTargets) {
      test('$target passes \$(FF_OBFUSCATE)', () {
        final recipe = recipes[target];
        expect(
          recipe,
          isNotNull,
          reason: 'target "$target" no longer exists in the Makefile — if it was '
              'renamed, update this list; if it was removed, remove it here too.',
        );
        expect(
          recipe,
          contains(r'$(FF_OBFUSCATE)'),
          reason: 'release target "$target" builds without --obfuscate.',
        );
      });
    }
  });

  group('the shipped core options match the Go golden fixture', () {
    // hiddify-core/v2/config/golden_config_test.go pins the generated sing-box
    // config for the configuration this client actually sends. To do that it
    // hand-transcribes the values below into its `shipped()` helper, because
    // DefaultHiddifyOptions() on the Go side is NOT the shipped configuration —
    // it has the tun off, TUNStack "mixed", blocking off, DirectPort 12337 and a
    // bare 1.1.1.1 resolver.
    //
    // A hand transcription rots silently when only one side changes. This is the
    // other end of that loop: change a value here and this test fails, naming
    // the Go fixture that must change with it.
    //
    // This is a source-level pin, not a behavioural one — it reads the literals
    // out of the provider rather than building the provider, which would need a
    // full SharedPreferences harness for no extra signal. It catches the
    // realistic drift: someone edits the literal and forgets the Go side.
    final source = File('lib/features/settings/data/config_option_repository.dart')
        .readAsStringSync();

    const pinned = <String, String>{
      'region': 'region: "cn"',
      'enableTun': 'enableTun: true',
      'setSystemProxy': 'setSystemProxy: false',
      'strictRoute': 'strictRoute: true',
      'tunImplementation': 'tunImplementation: TunImplementation.gvisor',
      'directPort': 'directPort: 0',
      'tproxyPort': 'tproxyPort: 12335',
      'redirectPort': 'redirectPort: 12336',
      'mixedPort': 'mixedPort: kMixedPort',
      'kMixedPort value': 'kMixedPort = 12334',
      'remoteDnsAddress': 'remoteDnsAddress: "https://1.1.1.1/dns-query"',
      'remoteDnsDomainStrategy': 'remoteDnsDomainStrategy: DomainStrategy.ipv4Only',
      'directDnsAddress': 'directDnsAddress: "https://dns.alidns.com/dns-query"',
      'directDnsDomainStrategy': 'directDnsDomainStrategy: DomainStrategy.ipv4Only',
      'enableFakeDns': 'enableFakeDns: false',
      'bypassLan': 'bypassLan: false',
      'allowConnectionFromLan': 'allowConnectionFromLan: false',
      'enableClashApi': 'enableClashApi: true',
      'clashApiPort': '_kClashApiPort = 16756',
    };

    pinned.forEach((name, literal) {
      test('$name is unchanged', () {
        expect(
          source.contains(literal),
          isTrue,
          reason: 'Expected `$literal` in singboxConfigOptions. If this changed '
              'deliberately, update shipped() in '
              'hiddify-core/v2/config/golden_config_test.go and regenerate the '
              'goldens with -update in the same commit — otherwise the golden '
              'configs stop describing what ships.',
        );
      });
    });

    test('log level is compiled down to warn in release builds', () {
      // Both halves are load-bearing. Hiding the picker alone would leave a
      // previously-stored `trace` flowing to the core forever, since the level is
      // a persisted preference and it is the level — not the debug flag — that
      // dictates whether the core logs every connection destination and every DNS
      // lookup. DESIGN-INVARIANTS.md#debug-log-level-debug-builds-only
      expect(
        source.contains('logLevel: kDebugMode ? ref.watch(logLevel) : LogLevel.warn'),
        isTrue,
        reason: 'Release builds must pin logLevel to warn.',
      );
      expect(
        source.contains('logFile: kReleaseMode ? "" : "data/box.log"'),
        isTrue,
        reason: 'Release builds must write no log file.',
      );
    });
  });
}

List<File> _dartFilesUnder(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

List<File> _filesNamed(String dir, String name) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.uri.pathSegments.last == name)
    .toList();

/// Splits a Makefile into `target -> recipe text`.
///
/// Crude but sufficient: a recipe is every line after `target:` that begins with
/// a tab, plus the prerequisite line itself, stopping at the first line that
/// starts in column zero.
Map<String, String> _makeRecipes(String makefile) {
  final recipes = <String, String>{};
  final lines = makefile.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final match = RegExp('^([A-Za-z0-9_.-]+):(?!=)').firstMatch(lines[i]);
    if (match == null) continue;

    final buffer = StringBuffer(lines[i]);
    for (var j = i + 1; j < lines.length; j++) {
      final line = lines[j];
      if (line.isEmpty) continue;
      if (!line.startsWith('\t') && !line.startsWith(' ')) break;
      buffer.writeln(line);
    }
    recipes[match.group(1)!] = buffer.toString();
  }
  return recipes;
}
