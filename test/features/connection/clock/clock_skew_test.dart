import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/clock/model/clock_skew.dart';

/// The "device time is wrong" rules: what a response's `Date` says about the
/// device clock, and when the warning goes up and comes down.
void main() {
  final sentAt = DateTime.utc(2026, 11, 8, 12);

  ClockSample sample({required int deviceAheadSeconds, int roundTripMs = 200, String? age}) => ClockSample.fromResponse(
    sentAt: sentAt,
    receivedAt: sentAt.add(Duration(milliseconds: roundTripMs)),
    date: HttpDate.format(sentAt.subtract(Duration(seconds: deviceAheadSeconds))),
    age: age,
  )!;

  group('ClockSample.fromResponse', () {
    test('a device two minutes fast reads as +120 s', () {
      final s = sample(deviceAheadSeconds: 120);
      expect(s.skew.inSeconds, 120);
      expect(s.uncertainty, const Duration(milliseconds: 1100));
    });

    test('a slow device reads as negative', () {
      // -90 s, plus the half of the 200 ms round trip the device spent waiting.
      expect(sample(deviceAheadSeconds: -90).skew.inMilliseconds, -89900);
    });

    test('Age moves the server clock forward: a cached answer is older than now', () {
      // Device right, answer cached 40 s ago with its original Date.
      expect(sample(deviceAheadSeconds: 40, age: '40').skew.inSeconds, 0);
    });

    test('a long round trip widens the uncertainty', () {
      expect(sample(deviceAheadSeconds: 0, roundTripMs: 20000).uncertainty, const Duration(seconds: 11));
    });

    test('no sample from a missing or unparseable Date', () {
      expect(ClockSample.fromResponse(sentAt: sentAt, receivedAt: sentAt, date: null), isNull);
      expect(ClockSample.fromResponse(sentAt: sentAt, receivedAt: sentAt, date: 'yesterday'), isNull);
    });

    test('no sample when the clock moved during the request, or it took over a minute', () {
      final date = HttpDate.format(sentAt);
      expect(
        ClockSample.fromResponse(sentAt: sentAt, receivedAt: sentAt.subtract(const Duration(seconds: 1)), date: date),
        isNull,
      );
      expect(
        ClockSample.fromResponse(sentAt: sentAt, receivedAt: sentAt.add(const Duration(seconds: 61)), date: date),
        isNull,
      );
    });

    test('a nonsense Age counts as none', () {
      expect(sample(deviceAheadSeconds: 120, age: 'soon').skew.inSeconds, 120);
      expect(sample(deviceAheadSeconds: 120, age: '-5').skew.inSeconds, 120);
    });
  });

  group('isCertificateDateFailure', () {
    test('an expired or not-yet-valid certificate is a date problem', () {
      expect(
        isCertificateDateFailure(
          const HandshakeException(
            'Handshake error in client',
            OSError('CERTIFICATE_VERIFY_FAILED: certificate has expired(handshake.cc:393)'),
          ),
        ),
        isTrue,
      );
      expect(
        isCertificateDateFailure(
          const HandshakeException(
            'Handshake error in client',
            OSError('CERTIFICATE_VERIFY_FAILED: certificate is not yet valid(handshake.cc:393)'),
          ),
        ),
        isTrue,
      );
    });

    test('any other handshake failure, or any other error, is not', () {
      expect(
        isCertificateDateFailure(
          const HandshakeException(
            'Handshake error in client',
            OSError('CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate'),
          ),
        ),
        isFalse,
      );
      expect(isCertificateDateFailure(const SocketException('connection refused')), isFalse);
      expect(isCertificateDateFailure(null), isFalse);
    });
  });

  group('ClockTracker', () {
    const t0 = Duration(minutes: 5);

    test('raises at 30 s off beyond doubt, in either direction', () {
      final tracker = ClockTracker();
      expect(tracker.sample(sample(deviceAheadSeconds: 120), t0), ClockEffect.raised);
      expect(tracker.issue?.skew?.inSeconds, 120);

      final slow = ClockTracker();
      expect(slow.sample(sample(deviceAheadSeconds: -45), t0), ClockEffect.raised);
    });

    test('does not raise when the uncertainty could account for it', () {
      final tracker = ClockTracker();
      // 32 s off at the middle of a 24 s round trip: anywhere from 19 to 45 s.
      expect(tracker.sample(sample(deviceAheadSeconds: 20, roundTripMs: 24000), t0), ClockEffect.none);
      expect(tracker.issue, isNull);
    });

    test('a clock a few seconds off raises nothing', () {
      final tracker = ClockTracker();
      expect(tracker.sample(sample(deviceAheadSeconds: 3), t0), ClockEffect.none);
      expect(tracker.issue, isNull);
    });

    test('clears only once the clock is clearly right again', () {
      final tracker = ClockTracker()..sample(sample(deviceAheadSeconds: 120), t0);
      // Between the thresholds: no change either way.
      expect(tracker.sample(sample(deviceAheadSeconds: 25), t0), ClockEffect.none);
      expect(tracker.issue, isNotNull);
      expect(tracker.sample(sample(deviceAheadSeconds: 1), t0), ClockEffect.cleared);
      expect(tracker.issue, isNull);
    });

    test('a certificate dated as expired raises without an offset; a good answer clears it', () {
      final tracker = ClockTracker();
      expect(tracker.certificateDatesRejected(t0), ClockEffect.raised);
      expect(tracker.issue, const ClockIssue(skew: null));
      expect(tracker.sample(sample(deviceAheadSeconds: 0), t0), ClockEffect.cleared);
    });

    test('a dismissal lasts as long as the warning', () {
      final tracker = ClockTracker()..sample(sample(deviceAheadSeconds: 120), t0);
      tracker.dismiss();
      expect(tracker.issue?.dismissed, isTrue);
      tracker.sample(sample(deviceAheadSeconds: 121), t0);
      expect(tracker.issue?.dismissed, isTrue, reason: 'the same wrong clock again');
      tracker
        ..sample(sample(deviceAheadSeconds: 0), t0)
        ..sample(sample(deviceAheadSeconds: 120), t0);
      expect(tracker.issue?.dismissed, isFalse, reason: 'a later wrong clock shows again');
    });

    test('explains a dead tunnel only on recent evidence', () {
      final tracker = ClockTracker();
      expect(tracker.explains(t0), isFalse);
      tracker.sample(sample(deviceAheadSeconds: 120), t0);
      expect(tracker.explains(t0 + const Duration(minutes: 29)), isTrue);
      expect(
        tracker.explains(t0 + clockEvidenceFreshFor),
        isFalse,
        reason: 'an old reading must not hide a real hub outage',
      );
      // Fresh evidence renews it.
      tracker.sample(sample(deviceAheadSeconds: 120), t0 + const Duration(minutes: 40));
      expect(tracker.explains(t0 + const Duration(minutes: 41)), isTrue);
    });
  });
}
