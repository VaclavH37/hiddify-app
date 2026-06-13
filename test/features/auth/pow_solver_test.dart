// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/pow_solver.dart';

void main() {
  group('leadingZeroBits', () {
    test('all-zero digest counts every bit', () {
      expect(leadingZeroBits(List<int>.filled(32, 0)), 256);
    });

    test('first non-zero byte stops the scan', () {
      // 0x00 (8) + 0x0F (4 leading zeros) = 12, then stop.
      expect(leadingZeroBits([0x00, 0x0F, 0xFF, 0xFF]), 12);
      // difficulty-20 example from the spec: 2 full zero bytes + third <= 0x0F.
      expect(leadingZeroBits([0x00, 0x00, 0x0F]), 20);
    });

    test('leading one bit means zero', () {
      expect(leadingZeroBits([0x80, 0x00]), 0);
    });
  });

  group('meetsDifficulty', () {
    test('hash input is verbatim "challenge:nonce" UTF-8', () {
      const challenge = 'abc';
      const nonce = '42';
      // Independently recompute to lock the exact input shape the server uses.
      final expected = sha256.convert(utf8.encode('abc:42')).bytes;
      final zeros = leadingZeroBits(expected);
      expect(meetsDifficulty(challenge, nonce, zeros), isTrue);
      expect(meetsDifficulty(challenge, nonce, zeros + 1), isFalse);
    });
  });

  group('solvePow', () {
    test('returns a nonce that satisfies the difficulty', () async {
      const challenge = 'rayn-test-challenge';
      const difficulty = 12; // small enough to be fast, real enough to exercise the loop
      final nonce = await solvePow(challenge, difficulty);
      expect(meetsDifficulty(challenge, nonce, difficulty), isTrue);
    });

    test('the synchronous entrypoint agrees with the async wrapper', () {
      const challenge = 'rayn-test-challenge-2';
      const difficulty = 10;
      final nonce = solvePowEntry(<dynamic>[challenge, difficulty]);
      expect(meetsDifficulty(challenge, nonce, difficulty), isTrue);
    });
  });
}
