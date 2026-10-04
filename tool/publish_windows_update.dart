// Publishes a Windows release to the updater, and manages its signing key.
//
//   dart run tool/publish_windows_update.dart keygen --key-id k1 --out <file>
//   dart run tool/publish_windows_update.dart publish --key <file> [--channel stable|test]
//       [--installer <path>] [--important] [--dry-run]
//   dart run tool/publish_windows_update.dart verify [--channel stable|test]
//
// THE SIGNING KEY IS THE UPDATER'S TRUST ROOT. Every Windows install runs what
// it signs, as administrator. Keep the key file offline and backed up, never in
// this repository or CI. It is encrypted with a passphrase, read from the
// console (echo off) or from RAYN_UPDATE_KEY_PASSPHRASE; never from argv,
// which process listings show.
//
// publish, in order:
//   1. reads the version from pubspec.yaml and finds dist/<ver>+<build>/…exe;
//   2. refuses a build that is not newer than the live manifest's;
//   3. signs the manifest and verifies it with the keys this repository pins
//      (lib/core/app_update/update_keys.dart), so a release the app would
//      reject never goes out;
//   4. writes everything to build/app-update/<channel>/ for inspection;
//   5. unless --dry-run, uploads to R2 with the AWS CLI, the installer first
//      and the manifest last, then reads both back through cdn.raynlabs.io.
//
// Upload needs R2_ACCOUNT_ID, R2_BUCKET, AWS_ACCESS_KEY_ID and
// AWS_SECRET_ACCESS_KEY in the environment (an R2 token with Object Read &
// Write on the bucket).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hiddify/core/app_update/update_keys.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/app_update/update_signing.dart';

const _defaultBase = 'https://cdn.raynlabs.io';
const _channels = {'stable', 'test'};

Future<void> main(List<String> args) async {
  if (args.isEmpty) _usage();
  final command = args.first;
  final options = _parseOptions(args.skip(1).toList());
  try {
    switch (command) {
      case 'keygen':
        await _keygen(options);
      case 'publish':
        await _publish(options);
      case 'verify':
        await _verify(options);
      default:
        _usage();
    }
  } on _ToolError catch (e) {
    stderr.writeln('error: ${e.message}');
    exit(1);
  } on UpdateManifestException catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  } on UpdateKeyFileException catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  }
}

class _ToolError implements Exception {
  _ToolError(this.message);
  final String message;
}

Never _usage() {
  stderr.writeln('usage:');
  stderr.writeln('  keygen  --key-id <id> --out <file>');
  stderr.writeln('  publish --key <file> [--channel stable|test] [--installer <path>] [--important] [--dry-run]');
  stderr.writeln('  verify  [--channel stable|test]');
  exit(64);
}

Map<String, String> _parseOptions(List<String> args) {
  final options = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) throw _ToolError('unexpected argument $arg');
    final name = arg.substring(2);
    if (const {'important', 'dry-run'}.contains(name)) {
      options[name] = 'true';
    } else {
      if (i + 1 >= args.length) throw _ToolError('--$name needs a value');
      options[name] = args[++i];
    }
  }
  return options;
}

String _channel(Map<String, String> options) {
  final channel = options['channel'] ?? 'stable';
  if (!_channels.contains(channel)) throw _ToolError('channel must be one of ${_channels.join(', ')}');
  return channel;
}

String _base(Map<String, String> options) => (options['base'] ?? _defaultBase).replaceAll(RegExp(r'/+$'), '');

// --- keygen -----------------------------------------------------------------

Future<void> _keygen(Map<String, String> options) async {
  final keyId = options['key-id'] ?? (throw _ToolError('--key-id is required'));
  if (!RegExp(r'^[a-z0-9-]{1,16}$').hasMatch(keyId)) throw _ToolError('--key-id: lowercase letters, digits, dashes');
  final out = File(options['out'] ?? (throw _ToolError('--out is required')));
  if (out.existsSync()) throw _ToolError('${out.path} exists; refusing to overwrite a key');

  final passphrase = _readPassphrase('New passphrase (12+ characters): ');
  if (passphrase.length < 12) throw _ToolError('passphrase too short');
  if (Platform.environment['RAYN_UPDATE_KEY_PASSPHRASE'] == null &&
      _readPassphrase('Repeat passphrase: ') != passphrase) {
    throw _ToolError('passphrases differ');
  }

  final pair = generateUpdateKeyPair();
  stdout.writeln('deriving the key-file key (up to half a minute)…');
  out.writeAsStringSync(
    encryptUpdateKeyFile(key: pair.privateKey, publicKey: pair.publicKey, keyId: keyId, passphrase: passphrase),
  );
  stdout
    ..writeln('wrote ${out.path}. Keep it offline and back it up; it cannot be recovered.')
    ..writeln('add this line to kUpdatePublicKeys in lib/core/app_update/update_keys.dart:')
    ..writeln("  '$keyId': '${encodeUpdatePublicKey(pair.publicKey)}',");
}

String _readPassphrase(String prompt) {
  final fromEnv = Platform.environment['RAYN_UPDATE_KEY_PASSPHRASE'];
  if (fromEnv != null) return fromEnv;
  stdout.write(prompt);
  try {
    stdin.echoMode = false;
  } on StdinException {
    throw _ToolError('cannot hide input in this terminal; run from cmd/PowerShell or set RAYN_UPDATE_KEY_PASSPHRASE');
  }
  try {
    return stdin.readLineSync() ?? '';
  } finally {
    stdin.echoMode = true;
    stdout.writeln();
  }
}

// --- publish ----------------------------------------------------------------

Future<void> _publish(Map<String, String> options) async {
  final channel = _channel(options);
  final base = _base(options);
  final dryRun = options['dry-run'] == 'true';
  final keyFile = File(options['key'] ?? (throw _ToolError('--key is required')));
  if (!keyFile.existsSync()) throw _ToolError('${keyFile.path} not found');

  final (version, build) = _pubspecVersion();
  final installer = File(options['installer'] ?? 'dist/$version+$build/RaynVPN-$version+$build-windows.exe');
  if (!installer.existsSync()) throw _ToolError('${installer.path} not found; build it with make windows-exe-release');
  final size = installer.lengthSync();
  if (size > kUpdateMaxInstallerBytes) throw _ToolError('installer is $size bytes, over the cap');

  final live = await _fetchLive(base, channel);
  if (live != null && build <= live.build) {
    throw _ToolError('build $build is not newer than the live $channel build ${live.build} (${live.version})');
  }

  stdout.writeln('hashing ${installer.path} ($size bytes)…');
  final digest = (await sha256.bind(installer.openRead()).first).toString();
  final remotePath = 'app/windows/RaynVPN-$version-$build-windows.exe';
  final manifest = UpdateManifest(
    schema: kUpdateManifestSchema,
    platform: 'windows',
    channel: channel,
    version: version,
    build: build,
    publishedAt: DateTime.now().toUtc(),
    important: options['important'] == 'true',
    installer: UpdateInstaller(path: remotePath, size: size, sha256: digest),
  );

  final opened = decryptUpdateKeyFile(keyFile.readAsStringSync(), _readPassphrase('Key passphrase: '));
  final payload = encodeUpdatePayload(manifest);
  final envelope = signUpdateEnvelope(payload: payload, keyId: opened.keyId, key: opened.key);

  // What clients will do with it: refuse to publish anything they would reject.
  if (!kUpdatePublicKeys.containsKey(opened.keyId)) {
    throw _ToolError(
      'key ${opened.keyId} is not in update_keys.dart; ship a build that trusts it before publishing with it',
    );
  }
  verifyUpdateEnvelope(envelope, kUpdatePublicKeys);

  final outDir = Directory('build/app-update/$channel')..createSync(recursive: true);
  File('${outDir.path}/MANIFEST').writeAsStringSync(envelope);
  File('${outDir.path}/payload.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
  stdout
    ..writeln('signed $channel $version ($build) with ${opened.keyId}; important: ${manifest.important}')
    ..writeln('  installer  $remotePath  $size  ${digest.substring(0, 16)}…')
    ..writeln('  written to ${outDir.path}/');
  if (dryRun) {
    stdout.writeln('dry run: nothing uploaded');
    return;
  }

  final r2 = _R2.fromEnvironment();
  if (await r2.exists(remotePath)) {
    stdout.writeln('installer already in the bucket; not re-uploading');
  } else {
    await r2.put(
      remotePath,
      installer.path,
      contentType: 'application/octet-stream',
      cacheControl: 'public, max-age=31536000, immutable',
    );
    stdout.writeln('uploaded the installer');
  }
  await r2.put(
    'app/windows/$channel/MANIFEST',
    '${outDir.path}/MANIFEST',
    contentType: 'application/json',
    cacheControl: 'public, max-age=300',
  );
  stdout.writeln('uploaded the manifest');

  final served = await _get('$base/app/windows/$channel/MANIFEST?check=${manifest.build}');
  if (served == null || served.trim() != envelope.trim()) {
    throw _ToolError('the CDN does not serve the manifest just uploaded');
  }
  final head = await _head('$base/$remotePath?check=${manifest.build}');
  if (head != size) throw _ToolError('the CDN serves the installer with length $head, expected $size');
  stdout.writeln('verified through $base: manifest and installer are live');
}

(String, int) _pubspecVersion() {
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync());
  if (match == null) throw _ToolError('pubspec.yaml has no version: x.y.z+build line');
  return (match[1]!, int.parse(match[2]!));
}

// --- verify -----------------------------------------------------------------

Future<void> _verify(Map<String, String> options) async {
  final channel = _channel(options);
  final live = await _fetchLive(_base(options), channel);
  if (live == null) {
    stdout.writeln('no $channel manifest is published');
    return;
  }
  stdout
    ..writeln('$channel: ${live.version} (${live.build}), published ${live.publishedAt.toIso8601String()}')
    ..writeln('  important: ${live.important}')
    ..writeln('  installer: ${live.installer.path}  ${live.installer.size}  ${live.installer.sha256}');
}

/// The live manifest, verified against the keys this repository pins, or null
/// when none is published. A manifest that fails verification is an error.
Future<UpdateManifest?> _fetchLive(String base, String channel) async {
  final body = await _get('$base/app/windows/$channel/MANIFEST?check=${DateTime.now().millisecondsSinceEpoch}');
  if (body == null) return null;
  return verifyUpdateEnvelope(body, kUpdatePublicKeys);
}

// --- HTTP and R2 ------------------------------------------------------------

Future<String?> _get(String url) async {
  final client = HttpClient()..userAgent = 'rayn-publish-windows-update';
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode == 404) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != 200) throw _ToolError('GET $url answered ${response.statusCode}');
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

Future<int> _head(String url) async {
  final client = HttpClient()..userAgent = 'rayn-publish-windows-update';
  try {
    final response = await (await client.headUrl(Uri.parse(url))).close();
    await response.drain<void>();
    if (response.statusCode != 200) throw _ToolError('HEAD $url answered ${response.statusCode}');
    return response.contentLength;
  } finally {
    client.close();
  }
}

class _R2 {
  _R2(this.accountId, this.bucket);

  factory _R2.fromEnvironment() {
    final env = Platform.environment;
    final missing = [
      'R2_ACCOUNT_ID',
      'R2_BUCKET',
      'AWS_ACCESS_KEY_ID',
      'AWS_SECRET_ACCESS_KEY',
    ].where((name) => (env[name] ?? '').isEmpty).toList();
    if (missing.isNotEmpty) throw _ToolError('missing environment: ${missing.join(', ')}');
    return _R2(env['R2_ACCOUNT_ID']!, env['R2_BUCKET']!);
  }

  final String accountId;
  final String bucket;

  Map<String, String> get _env => {
    ...Platform.environment,
    'AWS_DEFAULT_REGION': 'auto',
    'AWS_REQUEST_CHECKSUM_CALCULATION': 'when_required',
    'AWS_RESPONSE_CHECKSUM_VALIDATION': 'when_required',
  };

  List<String> get _target => ['--bucket', bucket, '--endpoint-url', 'https://$accountId.r2.cloudflarestorage.com'];

  Future<bool> exists(String key) async {
    final result = await Process.run('aws', ['s3api', 'head-object', '--key', key, ..._target], environment: _env);
    return result.exitCode == 0;
  }

  Future<void> put(String key, String path, {required String contentType, required String cacheControl}) async {
    final result = await Process.run('aws', [
      's3api',
      'put-object',
      '--key',
      key,
      '--body',
      path,
      '--content-type',
      contentType,
      '--cache-control',
      cacheControl,
      ..._target,
    ], environment: _env);
    if (result.exitCode != 0) throw _ToolError('upload of $key failed: ${(result.stderr as String).trim()}');
  }
}
