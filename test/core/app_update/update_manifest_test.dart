import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_update/update_keys.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/app_update/update_signing.dart';
import 'package:pointycastle/export.dart' show ECPrivateKey;

/// The Windows updater installs, as administrator, whatever a verified
/// manifest points at. These pin the verification: only a signature from a
/// pinned key over the exact payload bytes passes, and the payload must
/// describe one bounded installer under app/windows/.
void main() {
  final pair = generateUpdateKeyPair(Random(1));
  final other = generateUpdateKeyPair(Random(2));
  final pinned = {'k1': encodeUpdatePublicKey(pair.publicKey)};

  UpdateManifest manifest({
    String platform = 'windows',
    String path = 'app/windows/RaynVPN-1.6.2-10602-windows.exe',
    int size = 32883242,
    String sha256 = 'aa',
    int build = 10602,
  }) => UpdateManifest(
    schema: kUpdateManifestSchema,
    platform: platform,
    channel: 'stable',
    version: '1.6.2',
    build: build,
    publishedAt: DateTime.utc(2026, 10, 20, 9),
    important: false,
    installer: UpdateInstaller(path: path, size: size, sha256: sha256.padRight(64, '0')),
  );

  String sign(List<int> payload, {String keyId = 'k1', ECPrivateKey? key}) =>
      signUpdateEnvelope(payload: payload, keyId: keyId, key: key ?? pair.privateKey);

  group('verifyUpdateEnvelope', () {
    test('accepts a manifest signed by a pinned key, and returns it', () {
      final verified = verifyUpdateEnvelope(sign(encodeUpdatePayload(manifest())), pinned);
      expect(verified.version, '1.6.2');
      expect(verified.build, 10602);
      expect(verified.publishedAt, DateTime.utc(2026, 10, 20, 9));
      expect(verified.installer.path, 'app/windows/RaynVPN-1.6.2-10602-windows.exe');
    });

    test('signing is deterministic', () {
      final payload = encodeUpdatePayload(manifest());
      expect(sign(payload), sign(payload));
    });

    test('refuses a payload changed after signing', () {
      final envelope = jsonDecode(sign(encodeUpdatePayload(manifest()))) as Map<String, dynamic>;
      final tampered = encodeUpdatePayload(manifest(sha256: 'bb'));
      envelope['payload'] = base64.encode(tampered);
      expect(() => verifyUpdateEnvelope(jsonEncode(envelope), pinned), throwsA(_rejected('does not verify')));
    });

    test('refuses a signature by a key the build does not pin', () {
      final envelope = sign(encodeUpdatePayload(manifest()), key: other.privateKey);
      expect(() => verifyUpdateEnvelope(envelope, pinned), throwsA(_rejected('does not verify')));
    });

    test('refuses a key id the build does not pin', () {
      final envelope = sign(encodeUpdatePayload(manifest()), keyId: 'k9');
      expect(() => verifyUpdateEnvelope(envelope, pinned), throwsA(_rejected('not trusted')));
    });

    test('nothing verifies when no key is pinned', () {
      expect(() => verifyUpdateEnvelope(sign(encodeUpdatePayload(manifest())), const {}), throwsA(_rejected('')));
    });

    test('refuses malformed envelopes', () {
      for (final bad in [
        'not json',
        '[]',
        '{"key_id":"k1"}',
        '{"key_id":"k1","payload":"!!","signature":"!!"}',
        jsonEncode({
          'key_id': 'k1',
          'payload': base64.encode([1]),
          'signature': base64.encode(List.filled(10, 0)),
        }),
      ]) {
        expect(() => verifyUpdateEnvelope(bad, pinned), throwsA(isA<UpdateManifestException>()), reason: bad);
      }
    });

    test('a validly signed payload must still be a valid manifest', () {
      final payload = utf8.encode(jsonEncode({...manifest().toJson(), 'schema': 2}));
      expect(() => verifyUpdateEnvelope(sign(payload), pinned), throwsA(_rejected('schema')));
    });
  });

  group('UpdateManifest.fromJson', () {
    Map<String, dynamic> json({Map<String, dynamic> override = const {}, Map<String, dynamic>? installer}) => {
      ...manifest().toJson(),
      ...override,
      if (installer != null) 'installer': {...manifest().installer.toJson(), ...installer},
    };

    test('round-trips', () {
      final parsed = UpdateManifest.fromJson(json());
      expect(parsed.toJson(), manifest().toJson());
    });

    test('the installer must be one .exe directly under app/windows/', () {
      for (final path in [
        'app/windows/../evil.exe',
        'app/windows/sub/RaynVPN.exe',
        'app/linux/RaynVPN.exe',
        '/app/windows/RaynVPN.exe',
        'https://evil.example/RaynVPN.exe',
        'app/windows/RaynVPN.msi',
        'app/windows/Rayn VPN.exe',
        'app/windows/RaynVPN+1.exe',
      ]) {
        expect(
          () => UpdateManifest.fromJson(json(installer: {'path': path})),
          throwsA(isA<UpdateManifestException>()),
          reason: path,
        );
      }
    });

    test('size must be positive and within the cap', () {
      for (final size in [0, -1, kUpdateMaxInstallerBytes + 1]) {
        expect(() => UpdateManifest.fromJson(json(installer: {'size': size})), throwsA(isA<UpdateManifestException>()));
      }
    });

    test('sha256 must be 64 lowercase hex characters', () {
      for (final digest in ['ab', 'Z' * 64, 'A' * 64]) {
        expect(
          () => UpdateManifest.fromJson(json(installer: {'sha256': digest})),
          throwsA(isA<UpdateManifestException>()),
        );
      }
    });

    test('published_at must be a UTC timestamp', () {
      for (final time in ['2026-10-20', '2026-10-20T09:00:00', '2026-10-20T09:00:00+08:00', 'soon']) {
        expect(
          () => UpdateManifest.fromJson(json(override: {'published_at': time})),
          throwsA(isA<UpdateManifestException>()),
          reason: time,
        );
      }
    });

    test('every field is required and typed', () {
      for (final key in [
        'schema',
        'platform',
        'channel',
        'version',
        'build',
        'published_at',
        'important',
        'installer',
      ]) {
        final broken = json()..remove(key);
        expect(() => UpdateManifest.fromJson(broken), throwsA(isA<UpdateManifestException>()), reason: key);
      }
      expect(
        () => UpdateManifest.fromJson(json(override: {'build': '10602'})),
        throwsA(isA<UpdateManifestException>()),
      );
      expect(() => UpdateManifest.fromJson(json(override: {'build': 0})), throwsA(isA<UpdateManifestException>()));
    });
  });

  group('key file', () {
    String keyFile({String passphrase = 'correct horse battery'}) => encryptUpdateKeyFile(
      key: pair.privateKey,
      publicKey: pair.publicKey,
      keyId: 'k1',
      passphrase: passphrase,
      iterations: 1000,
      random: Random(3),
    );

    test('opens with the right passphrase and signs envelopes the pinned key verifies', () {
      final opened = decryptUpdateKeyFile(keyFile(), 'correct horse battery');
      expect(opened.keyId, 'k1');
      expect(encodeUpdatePublicKey(opened.publicKey), pinned['k1']);
      final envelope = signUpdateEnvelope(
        payload: encodeUpdatePayload(manifest()),
        keyId: opened.keyId,
        key: opened.key,
      );
      expect(verifyUpdateEnvelope(envelope, pinned).build, 10602);
    });

    test('refuses a wrong passphrase', () {
      expect(() => decryptUpdateKeyFile(keyFile(), 'wrong'), throwsA(isA<UpdateKeyFileException>()));
    });

    test('refuses a file whose key id or public key was edited', () {
      final file = jsonDecode(keyFile()) as Map<String, dynamic>;
      final renamed = {...file, 'key_id': 'k2'};
      expect(
        () => decryptUpdateKeyFile(jsonEncode(renamed), 'correct horse battery'),
        throwsA(isA<UpdateKeyFileException>()),
      );
      final swapped = {...file, 'public_key': encodeUpdatePublicKey(other.publicKey)};
      expect(
        () => decryptUpdateKeyFile(jsonEncode(swapped), 'correct horse battery'),
        throwsA(isA<UpdateKeyFileException>()),
      );
    });

    test('does not contain the private scalar in the clear', () {
      final scalarHex = pair.privateKey.d!.toRadixString(16);
      expect(keyFile().contains(scalarHex), isFalse);
    });
  });

  // A bad paste here would silently turn every update into "rejected".
  test('every pinned key is a valid P-256 public key', () {
    for (final MapEntry(key: id, value: key) in kUpdatePublicKeys.entries) {
      expect(id, matches(RegExp(r'^[a-z0-9-]{1,16}$')), reason: id);
      expect(() => decodeUpdatePublicKey(key), returnsNormally, reason: id);
    }
  });

  test('public keys round-trip through their base64 form', () {
    final encoded = encodeUpdatePublicKey(pair.publicKey);
    expect(base64.decode(encoded).length, 65);
    expect(decodeUpdatePublicKey(encoded).Q, pair.publicKey.Q);
  });
}

Matcher _rejected(String reasonPart) =>
    isA<UpdateManifestException>().having((e) => e.reason, 'reason', contains(reasonPart));
