import 'dart:io' show HandshakeException, HttpDate;

import 'package:flutter/foundation.dart';

/// How far off the device clock must be, beyond doubt, before the app says so.
///
/// The hubs' REALITY handshake rejects a client whose clock is more than 60 s
/// away from the hub's own (`maxTimeDiff` in the hub profile), and the client
/// stamps that handshake with the raw device clock. Half the window leaves room
/// for the hub's own drift and for this estimate's error.
const clockSkewRaiseThreshold = Duration(seconds: 30);

/// How close the clock must be, beyond doubt, before a raised warning clears.
/// Lower than the raise threshold so a clock near it does not flicker.
const clockSkewClearThreshold = Duration(seconds: 20);

/// How long the evidence behind a raised warning explains a dead tunnel to the
/// hub-reachability ladder. Older evidence still shows the banner, but no longer
/// stops a failover: a stale reading must never hide a real hub outage.
const clockEvidenceFreshFor = Duration(minutes: 30);

/// A request slower than this says too little about when its answer was made.
const _longestUsefulRoundTrip = Duration(seconds: 60);

/// One comparison of the device clock with a server's, from an HTTP response.
@immutable
class ClockSample {
  const ClockSample({required this.skew, required this.uncertainty});

  /// Device clock minus server clock: positive when the device is ahead.
  final Duration skew;

  /// How far [skew] may be from the truth: half the round trip, since the
  /// server stamped `Date` somewhere inside it, plus the second `Date` drops.
  final Duration uncertainty;

  /// The sample a response carries, or null when it carries none: no `Date`,
  /// an unparseable one, or a round trip too long or too odd (the clock moved
  /// while the request was out) to say anything.
  ///
  /// [sentAt] and [receivedAt] are device time, read just before the request
  /// and just after the response. [age] is the response's `Age` header: a
  /// cached answer carries the `Date` it was first made with, and `Age` says how
  /// much older than now that is.
  static ClockSample? fromResponse({
    required DateTime sentAt,
    required DateTime receivedAt,
    required String? date,
    String? age,
  }) {
    if (date == null) return null;
    final DateTime serverDate;
    try {
      serverDate = HttpDate.parse(date.trim());
    } on Object {
      return null;
    }
    final roundTrip = receivedAt.difference(sentAt);
    if (roundTrip.isNegative || roundTrip > _longestUsefulRoundTrip) return null;

    final ageSeconds = age == null ? 0 : int.tryParse(age.trim()) ?? 0;
    final serverNow = serverDate.add(Duration(seconds: ageSeconds < 0 ? 0 : ageSeconds));
    final deviceAtStamp = sentAt.add(roundTrip ~/ 2);
    return ClockSample(
      skew: deviceAtStamp.difference(serverNow),
      uncertainty: roundTrip ~/ 2 + const Duration(seconds: 1),
    );
  }

  @override
  bool operator ==(Object other) => other is ClockSample && other.skew == skew && other.uncertainty == uncertainty;

  @override
  int get hashCode => Object.hash(skew, uncertainty);

  @override
  String toString() => 'ClockSample(skew: ${skew.inSeconds}s, ±${uncertainty.inSeconds}s)';
}

/// Whether [error], from a request to one of our own hosts, says the server's
/// certificate is outside its validity dates.
///
/// Our certificates are renewed long before they expire, so when that happens
/// the device's date is what is wrong, and by months or years. That is a clock
/// no `Date` header can measure: every HTTPS request fails before one arrives.
/// The wording is BoringSSL's; a platform that words it differently simply
/// never raises the warning this way.
bool isCertificateDateFailure(Object? error) {
  if (error is! HandshakeException) return false;
  final text = error.toString().toLowerCase();
  return text.contains('certificate_verify_failed') &&
      (text.contains('certificate has expired') || text.contains('not yet valid'));
}

/// The warning the home page shows.
@immutable
class ClockIssue {
  const ClockIssue({required this.skew, this.dismissed = false});

  /// The measured offset (positive: the device is ahead), or null when the
  /// evidence was a certificate the device dated as expired or not yet valid.
  final Duration? skew;

  final bool dismissed;

  @override
  bool operator ==(Object other) => other is ClockIssue && other.skew == skew && other.dismissed == dismissed;

  @override
  int get hashCode => Object.hash(skew, dismissed);
}

/// What the notifier has to do besides publishing [ClockTracker.issue].
enum ClockEffect {
  none,

  /// A new warning: log it.
  raised,

  /// The clock is right again.
  cleared,
}

/// The rules behind the "device time is wrong" warning, free of Riverpod and of
/// ambient time so each one is a plain test.
///
/// - A sample whose offset is at least [clockSkewRaiseThreshold] even at the
///   edge of its uncertainty raises the warning; one within
///   [clockSkewClearThreshold] even at the far edge clears it. Anything in
///   between changes nothing.
/// - A certificate dated as expired or not yet valid raises it without an
///   offset; a later good sample clears it, since that answer could only have
///   arrived over a certificate the device accepted.
/// - A dismissal lasts as long as the warning does.
/// - [explains] answers only on recent evidence ([clockEvidenceFreshFor]).
///
/// [now] is monotonic time (time since launch), not the wall clock: the wall
/// clock is the thing under suspicion.
class ClockTracker {
  ClockIssue? _issue;
  Duration? _evidenceAt;

  ClockIssue? get issue => _issue;

  ClockEffect sample(ClockSample sample, Duration now) {
    final off = sample.skew.abs();
    if (off - sample.uncertainty >= clockSkewRaiseThreshold) return _raise(sample.skew, now);
    if (off + sample.uncertainty < clockSkewClearThreshold) return _clear();
    return ClockEffect.none;
  }

  ClockEffect certificateDatesRejected(Duration now) => _raise(null, now);

  /// Whether a wrong clock explains a dead tunnel right now.
  bool explains(Duration now) {
    final at = _evidenceAt;
    return _issue != null && at != null && now - at < clockEvidenceFreshFor;
  }

  void dismiss() {
    final issue = _issue;
    if (issue != null) _issue = ClockIssue(skew: issue.skew, dismissed: true);
  }

  ClockEffect _raise(Duration? skew, Duration now) {
    final raised = _issue == null;
    _issue = ClockIssue(skew: skew ?? _issue?.skew, dismissed: _issue?.dismissed ?? false);
    _evidenceAt = now;
    return raised ? ClockEffect.raised : ClockEffect.none;
  }

  ClockEffect _clear() {
    if (_issue == null) return ClockEffect.none;
    _issue = null;
    _evidenceAt = null;
    return ClockEffect.cleared;
  }
}

/// Where the HTTP clients hand their clock evidence. Implemented by the
/// notifier; absent in tests that don't care.
abstract interface class ClockEvidenceSink {
  void sample(ClockSample sample);

  void certificateDatesRejected();
}
