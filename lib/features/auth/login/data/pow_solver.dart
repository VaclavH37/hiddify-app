import 'dart:convert';

import 'package:crypto/crypto.dart'; // sha256
import 'package:flutter/foundation.dart'; // compute

/// Proof-of-Work solver for the account/auth API's bot-gated endpoints.
///
/// The backend protects auth endpoints with Cloudflare Turnstile for the web
/// frontend; native clients can't run Turnstile, so they submit a PoW solution
/// instead. The server validation is unforgiving — this must match the
/// backend's `internal/service/pow.go` (`meetsDifficulty`, `leadingZeroBits`,
/// `SolvePoW`) byte-for-byte:
///
/// - The hash input is the UTF-8 bytes of `challenge + ":" + nonce`. The
///   separator is a single ASCII colon.
/// - The `challenge` string is used VERBATIM as returned (it is base64url
///   text). It is NOT base64-decoded before hashing.
/// - The nonce is the string you send back unchanged (its UTF-8 bytes are
///   hashed); the reference uses the decimal form of an incrementing counter.
/// - `difficulty` is the required number of leading zero bits in the digest,
///   counted MSB-first across the 32-byte SHA-256 output. It is server-
///   controlled — always read it from the challenge response, never hard-code.

/// Counts leading zero bits across the digest, most-significant bit first.
int leadingZeroBits(List<int> digest) {
  var count = 0;
  for (final b in digest) {
    if (b == 0) {
      count += 8;
      continue;
    }
    var x = b;
    while ((x & 0x80) == 0) {
      count++;
      x <<= 1;
    }
    break;
  }
  return count;
}

/// True iff SHA-256(`challenge:nonce`) has at least [difficulty] leading zero
/// bits.
bool meetsDifficulty(String challenge, String nonce, int difficulty) {
  final digest = sha256.convert(utf8.encode('$challenge:$nonce')).bytes;
  return leadingZeroBits(digest) >= difficulty;
}

/// Isolate entrypoint: args = [challenge, difficulty]. Returns the solving
/// nonce. Top-level (not a closure) so it can be sent to a background isolate.
String solvePowEntry(List<dynamic> args) {
  final challenge = args[0] as String;
  final difficulty = args[1] as int;
  var i = 0;
  while (true) {
    final nonce = i.toString();
    if (meetsDifficulty(challenge, nonce, difficulty)) return nonce;
    i++;
  }
}

/// Solve the challenge off the UI thread. A 20-bit solve is sub-second but
/// variable, so it always runs in a background isolate via [compute].
Future<String> solvePow(String challenge, int difficulty) =>
    compute(solvePowEntry, <dynamic>[challenge, difficulty]);
