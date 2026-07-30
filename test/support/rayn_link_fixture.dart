// Shared helpers for `rayn://import/<token>` cryptolink tests: the encrypt side
// of RAYN-LINK-SYMMETRIC-MIGRATION.md §4, plus the §8 conformance vectors.
//
// Deliberately NOT named `*_test.dart` so the runner doesn't collect it.
//
// This file must NEVER call `raynLinkKey()` — tests pin a known secret via
// [useTestSecret] so they behave identically whether or not RAYN_LINK_SECRET is
// set in the build environment.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:hiddify/utils/rayn_token.dart';
import 'package:pointycastle/api.dart' show AEADParameters, KeyParameter;
import 'package:pointycastle/block/aes.dart' show AESEngine;
import 'package:pointycastle/block/modes/gcm.dart' show GCMBlockCipher;

/// The secret every §8 vector was minted under.
const kConformanceSecret = 'rayn-link-conformance-vector-secret';

/// `SHA-256(utf8(kConformanceSecret))` — assert this first; if it doesn't match,
/// nothing downstream is meaningful.
const kConformanceKeyHex = 'f9c6e0885d81f9036bb4477a342c3a8fb81ed442ed98eb9b90564e160a4735b8';

/// §6.3 derivation table: a secret that *looks* like hex but must be hashed as
/// the 64 ASCII characters it is.
const kHexLookingSecret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
const kHexLookingSecretKeyHex = 'a8ae6e6ee929abea3afcfc5258c8ccd6f85273e0d4626d26c7279f3250f77c8e';

/// What you get if you wrongly hex-decode the secret to 32 bytes first.
const kHexDecodedWrongKeyHex = '4884fdaafea47c29fea7159d0daddd9c085d6200e1359e85bb81736af6b7c837';

const kRaynLinkPrefix = 'rayn://import/';
const kLinkVersionV2 = 0x02;

final _rand = Random.secure();

/// Pins the decryptor's key to [secret]'s derived key for the current test.
void useTestSecret([String secret = kConformanceSecret]) =>
    RaynTokenDecryptor.debugSetKey(RaynTokenDecryptor.deriveKey(secret));

/// Restores the embedded key (undoes [useTestSecret] / an explicit override).
void useEmbeddedKey() => RaynTokenDecryptor.debugClearKeyOverride();

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Mints the base64url payload — the part after `rayn://import/`.
String mintRaynToken(
  String url, {
  String secret = kConformanceSecret,
  int version = kLinkVersionV2,
  Uint8List? nonce,
}) =>
    mintRaynTokenBytes(
      Uint8List.fromList(utf8.encode(url)),
      secret: secret,
      version: version,
      nonce: nonce,
    );

/// Mints a full `rayn://import/…` link.
String mintRaynLink(
  String url, {
  String secret = kConformanceSecret,
  int version = kLinkVersionV2,
  Uint8List? nonce,
}) =>
    kRaynLinkPrefix + mintRaynToken(url, secret: secret, version: version, nonce: nonce);

/// Encrypts arbitrary bytes — for the "plaintext isn't valid UTF-8" case.
String mintRaynTokenBytes(
  Uint8List plaintext, {
  String secret = kConformanceSecret,
  int version = kLinkVersionV2,
  Uint8List? nonce,
}) {
  final key = RaynTokenDecryptor.deriveKey(secret);
  final iv = nonce ?? Uint8List.fromList(List<int>.generate(12, (_) => _rand.nextInt(256)));
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
  // Encrypt-mode `process` already appends the 16-byte tag.
  final ctAndTag = cipher.process(plaintext);

  final blob = Uint8List(1 + iv.length + ctAndTag.length)
    ..[0] = version
    ..setRange(1, 1 + iv.length, iv)
    ..setRange(1 + iv.length, 1 + iv.length + ctAndTag.length, ctAndTag);
  return base64Url.encode(blob).replaceAll('=', '');
}

String mintRaynLinkBytes(Uint8List plaintext, {String secret = kConformanceSecret}) =>
    kRaynLinkPrefix + mintRaynTokenBytes(plaintext, secret: secret);

/// Mints a valid link then flips one ciphertext bit — the V4 shape.
String mintCorruptedRaynLink(String url, {String secret = kConformanceSecret}) {
  final token = mintRaynToken(url, secret: secret);
  final blob = base64Url.decode(_pad(token));
  // Byte 14 is the first ciphertext byte (after version + 12-byte nonce).
  blob[14] ^= 0x01;
  return kRaynLinkPrefix + base64Url.encode(blob).replaceAll('=', '');
}

/// Re-encodes [blob] as a link without re-encrypting — for hand-built envelopes.
String linkFromBlob(List<int> blob) => kRaynLinkPrefix + base64Url.encode(Uint8List.fromList(blob)).replaceAll('=', '');

/// Decodes a link's payload back to raw blob bytes.
Uint8List blobOfLink(String link) => base64Url.decode(_pad(link.substring(kRaynLinkPrefix.length)));

String _pad(String s) {
  final mod = s.length % 4;
  return mod == 0 ? s : s + ('=' * (4 - mod));
}

// ---------------------------------------------------------------------------
// §8 conformance vectors — verbatim. Our backend's test suite pins the same V1,
// so if both sides pass, the two implementations agree on the wire format.
// ---------------------------------------------------------------------------

/// V1 — normal link, must decrypt. Plaintext is 63 bytes.
const kVectorV1 =
    'rayn://import/AqBXvnogxxBzjxwj3kdCF-ygyqKbWuTvPXB39g1R8smBzy8wuZ5nx2wg1fdZT4rNPan2Sw854MtlnoYCY2tHXjpq6aNz1g3HPRRV0qaBV220ztWnujj1HvC4qSo';
const kVectorV1Plain = 'https://sub1.example.com/s/AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';

/// V2 — 563-byte plaintext, 117 bytes over the old RSA-OAEP ceiling. This is the
/// regression vector: it could not have been produced under the previous scheme.
const kVectorV2 =
    'rayn://import/AuWyz_xATsOQ-CiAefs5jjibqxcrhrrTLINBRliglwJ6rhHiL4h_iBawpddPKJ67oKZMdPUEZlphoxINDXahYte9IY_XwUosAZDCvLBgqxj0oocUkSvEfkahcFxjXvNERWYlrbrjtstn7_EdSO_I8ZuPKftnYQJxmTjzY0E4fqH-nWevewEwT--Ic1MFnxsLzU7rqVuZ4Zuo6okmOCkvha8l3wM31MzbSuQVygOdGBdAmSgB7mVTB6GsR3fEIxOxrDEWFiUem4tWLigtFvYEqWdJ7Vg2wAZCOdYBgi7lJTPqWyUzrOGHjihzN1kZeJ_-WMWK0qhg21QvY5iSzpx74epiD73KkrkWXj0GTQp1qxJbd7M4EWrlFtgnK3NpgXwwSCMaQUuCr3ZLj3Bq8kfdVnf2IR1qRLE8svv0uwey69PkJLKV-KrqGSJRe5UMg0nj5d-DsP_jkALri03wRRG4z7oqUMwGoHnWS9tOPzEpv3QuOzktPo3_d-CpUNBb1jFmi1xEez7-J0gTi3gGVLjgotr2VJwHdA3jYYgnA3k6Nnqsz4ErJmfMQlPsu7820ZrK1nbMiAiJDtC4b3lpegCAysLiLkWWwGXemsSA0etqmXE8CTo09CAymkdXZQsT5ujMFiceXhBu4k3ehEYALMla8E4iYpfjP_HTEpEypvqXtSWHwXHw5-koHqIUX-oyfQngrvuc9SnNqZaOiPqmhU4aGvWaeFnSaBFSH1_p2fKE_5aU3EE9mLj_IixKWcUMGV4tDfsKe_GeOmyc-iXTU6w_2Q';
final kVectorV2Plain = 'https://subscription-primary.example.com/s/${'Q' * 520}';

/// V3 — version byte `0x01`. Must be rejected as UNSUPPORTED VERSION, not as an
/// authentication failure: this proves the version check runs before the AEAD open.
const kVectorV3 =
    'rayn://import/Ab4YU1uNpnzAG62go6JJMUiTqI2Fo7R6LoibNZgR9_wXT46KrE2vptkjranjwRwjOFNQAI5PG8Nr0Xyr7KPhAjNAyPnrYRrrkNsSWWanbMSc0iiKUTOzb44PReU';

/// V4 — valid version byte, one ciphertext bit flipped. Must fail authentication
/// and yield no plaintext.
const kVectorV4 =
    'rayn://import/AltrDXyPNFT2SLww4h2bfjplDO0HQ3EXK8OwrPbYKVVBKNHi0h5rADpI3hjm8cxQ-6NSAR8oE2gvwr6dXZtKTAZnyTnwxU0HChGO4IfZ2fbGinyUm2hB9BEzey8';
