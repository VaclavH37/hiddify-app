import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The Windows updater's manifest: what the newest release is, and the exact
/// installer that carries it.
///
/// An update runs code as administrator on every Windows install, so nothing
/// here is trusted until its signature verifies against a key pinned in the app
/// (`update_keys.dart`). The R2 bucket, the CDN and the mirror's CI can
/// withhold or delete an update; without the offline signing key they cannot
/// make a client install anything.
///
/// Wire format, at `https://cdn.raynlabs.io/app/windows/<channel>/MANIFEST`:
///
///     { "key_id": "k1",
///       "payload": "<base64 of the exact payload JSON bytes>",
///       "signature": "<base64 of r || s, 64 bytes>" }
///
/// The signature covers the payload bytes as sent, so there is no JSON
/// canonicalisation to get wrong. The payload:
///
///     { "schema": 1, "platform": "windows", "channel": "stable",
///       "version": "1.6.2", "build": 10602, "published_at": "2026-10-20T09:00:00Z",
///       "important": false,
///       "installer": { "path": "app/windows/RaynVPN-1.6.2-10602-windows.exe",
///                      "size": 32883242, "sha256": "…" } }
///
/// ECDSA P-256 with SHA-256: `pointycastle` has no Ed25519, and adding a
/// dependency for one verify is not worth it.
const kUpdateManifestSchema = 1;

/// The most a manifest may be. It is a few hundred bytes.
const kUpdateMaxManifestBytes = 16 * 1024;

/// The largest installer the updater will download. Today's is about 33 MB.
const kUpdateMaxInstallerBytes = 150 * 1024 * 1024;

final _sha256Hex = RegExp(r'^[0-9a-f]{64}$');
final _utcTimestamp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$');

/// An installer path inside the bucket: one file under `app/windows/`, no
/// directories, no `..`, no URL-special characters.
final _installerPath = RegExp(r'^app/windows/[A-Za-z0-9._-]+\.exe$');

/// Why a manifest was not accepted. The message names the check, never the
/// manifest's contents.
class UpdateManifestException implements Exception {
  const UpdateManifestException(this.reason);

  final String reason;

  @override
  String toString() => 'update manifest rejected: $reason';
}

class UpdateInstaller {
  const UpdateInstaller({required this.path, required this.size, required this.sha256});

  /// Bucket-relative, e.g. `app/windows/RaynVPN-1.6.2-10602-windows.exe`.
  final String path;
  final int size;

  /// Lowercase hex.
  final String sha256;

  Map<String, dynamic> toJson() => {'path': path, 'size': size, 'sha256': sha256};
}

class UpdateManifest {
  const UpdateManifest({
    required this.schema,
    required this.platform,
    required this.channel,
    required this.version,
    required this.build,
    required this.publishedAt,
    required this.important,
    required this.installer,
  });

  final int schema;
  final String platform;
  final String channel;

  /// For display only. [build] decides which release is newer.
  final String version;

  /// The pubspec build number (`1.6.2+10602` → 10602). Strictly increasing.
  final int build;
  final DateTime publishedAt;

  /// Prompt at every launch and offer no "skip this version". Never blocks
  /// connecting.
  final bool important;
  final UpdateInstaller installer;

  /// Strict: every field present and of the right type, the installer path a
  /// single `.exe` under `app/windows/`, the size within the cap.
  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    T field<T>(Map<String, dynamic> from, String key) {
      final value = from[key];
      if (value is! T) throw UpdateManifestException('$key is missing or has the wrong type');
      return value;
    }

    final schema = field<int>(json, 'schema');
    if (schema != kUpdateManifestSchema) throw UpdateManifestException('schema $schema is not supported');
    final platform = field<String>(json, 'platform');
    final channel = field<String>(json, 'channel');
    final version = field<String>(json, 'version');
    if (version.isEmpty || version.length > 32) throw const UpdateManifestException('version is malformed');
    final build = field<int>(json, 'build');
    if (build <= 0) throw const UpdateManifestException('build must be positive');
    final publishedRaw = field<String>(json, 'published_at');
    final publishedAt = _utcTimestamp.hasMatch(publishedRaw) ? DateTime.tryParse(publishedRaw)?.toUtc() : null;
    if (publishedAt == null) throw const UpdateManifestException('published_at is not a UTC timestamp');
    final important = field<bool>(json, 'important');

    final installerJson = field<Map<String, dynamic>>(json, 'installer');
    final path = field<String>(installerJson, 'path');
    if (!_installerPath.hasMatch(path) || path.contains('..')) {
      throw const UpdateManifestException('installer path is not a single .exe under app/windows/');
    }
    final size = field<int>(installerJson, 'size');
    if (size <= 0 || size > kUpdateMaxInstallerBytes) {
      throw const UpdateManifestException('installer size is out of range');
    }
    final sha256 = field<String>(installerJson, 'sha256');
    if (!_sha256Hex.hasMatch(sha256)) throw const UpdateManifestException('installer sha256 is malformed');

    return UpdateManifest(
      schema: schema,
      platform: platform,
      channel: channel,
      version: version,
      build: build,
      publishedAt: publishedAt,
      important: important,
      installer: UpdateInstaller(path: path, size: size, sha256: sha256),
    );
  }

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'platform': platform,
    'channel': channel,
    'version': version,
    'build': build,
    'published_at': _utcString(publishedAt),
    'important': important,
    'installer': installer.toJson(),
  };
}

String _utcString(DateTime time) => '${time.toUtc().toIso8601String().split('.').first}Z';

/// Verifies [envelopeJson] against [pinnedKeys] (key id → base64 SEC1
/// uncompressed P-256 public key) and returns the manifest it signs.
///
/// Throws [UpdateManifestException] for anything else: malformed envelope, a
/// key id the app does not pin, a bad signature, or a payload that fails
/// [UpdateManifest.fromJson]. The payload is only parsed after the signature
/// verifies.
UpdateManifest verifyUpdateEnvelope(String envelopeJson, Map<String, String> pinnedKeys) {
  final Object? decoded;
  try {
    decoded = jsonDecode(envelopeJson);
  } on FormatException {
    throw const UpdateManifestException('envelope is not JSON');
  }
  if (decoded is! Map<String, dynamic>) throw const UpdateManifestException('envelope is not an object');
  final keyId = decoded['key_id'];
  final payloadB64 = decoded['payload'];
  final signatureB64 = decoded['signature'];
  if (keyId is! String || payloadB64 is! String || signatureB64 is! String) {
    throw const UpdateManifestException('envelope fields are missing');
  }
  final pinned = pinnedKeys[keyId];
  if (pinned == null) throw UpdateManifestException('key $keyId is not trusted by this build');

  final Uint8List payload;
  final Uint8List signature;
  try {
    payload = base64.decode(payloadB64);
    signature = base64.decode(signatureB64);
  } on FormatException {
    throw const UpdateManifestException('envelope is not valid base64');
  }
  if (signature.length != 64) throw const UpdateManifestException('signature has the wrong length');

  if (!verifyUpdateSignature(payload, signature, decodeUpdatePublicKey(pinned))) {
    throw const UpdateManifestException('signature does not verify');
  }

  final Object? manifest;
  try {
    manifest = jsonDecode(utf8.decode(payload));
  } on FormatException {
    throw const UpdateManifestException('payload is not JSON');
  }
  if (manifest is! Map<String, dynamic>) throw const UpdateManifestException('payload is not an object');
  return UpdateManifest.fromJson(manifest);
}

/// ECDSA P-256 / SHA-256 over [message]; [signature] is r || s, 32 bytes each.
bool verifyUpdateSignature(List<int> message, List<int> signature, ECPublicKey key) {
  if (signature.length != 64) return false;
  final r = _bigInt(signature.sublist(0, 32));
  final s = _bigInt(signature.sublist(32));
  // verifySignature itself rejects r or s outside [1, n-1].
  final verifier = ECDSASigner(SHA256Digest())..init(false, PublicKeyParameter<ECPublicKey>(key));
  return verifier.verifySignature(Uint8List.fromList(message), ECSignature(r, s));
}

final updateCurve = ECDomainParameters('prime256v1');

/// A base64 SEC1 uncompressed point (65 bytes, `0x04 || X || Y`).
ECPublicKey decodeUpdatePublicKey(String base64Key) {
  final bytes = base64.decode(base64Key);
  if (bytes.length != 65 || bytes[0] != 0x04) throw const UpdateManifestException('pinned key is malformed');
  final point = updateCurve.curve.decodePoint(bytes);
  if (point == null) throw const UpdateManifestException('pinned key is not on the curve');
  return ECPublicKey(point, updateCurve);
}

String encodeUpdatePublicKey(ECPublicKey key) => base64.encode(key.Q!.getEncoded(false));

BigInt _bigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}
