import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/utils/rayn_link_key.dart';

/// Must match `_devSecret` in `tool/gen_rayn_link_key.dart`. Only used to prove
/// the reconstruction is inverse to the generator; a release build regenerates
/// the tables from the real secret and takes the `kRaynLinkKeyIsDev == false`
/// branch below.
const _devSecret = 'rayn-link-development-key-do-not-ship';

void main() {
  group('raynLinkKey', () {
    test('is a 32-byte AES-256 key', () {
      expect(raynLinkKey().length, 32);
    });

    test('reconstruction is inverse to the generator', () {
      if (!kRaynLinkKeyIsDev) {
        // Generated from the real RAYN_LINK_SECRET, whose value this test can't
        // know. The key-id invariant below still covers the round trip.
        return;
      }
      expect(raynLinkKey(), sha256.convert(utf8.encode(_devSecret)).bytes);
    });

    test('matches the key id the generator committed', () {
      // Holds for dev AND release tables: proves the emitted material really
      // reconstructs the key the generator derived, without knowing the secret.
      final id = sha256
          .convert(raynLinkKey())
          .bytes
          .sublist(0, 4)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      expect(id, kRaynLinkKeyId);
    });

    test('is stable across calls', () {
      // The intermediate scrub in raynLinkKey() must not corrupt the const
      // source tables it read from.
      expect(raynLinkKey(), raynLinkKey());
    });
  });
}
