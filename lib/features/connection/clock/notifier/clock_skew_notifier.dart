import 'dart:async';

import 'package:hiddify/features/connection/clock/model/clock_skew.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'clock_skew_notifier.g.dart';

/// The "device time is wrong" warning: null when there is nothing to say. The
/// rules are [ClockTracker]'s; this wires them to the app.
///
/// Fed by the HTTP clients that talk to our own servers (the subscription fetch
/// and the account API), which hand over every response's `Date` as a
/// [ClockSample]. No request is made for it, and nothing it learns leaves the
/// device.
///
/// Why it matters: the hubs' REALITY handshake carries the device clock and is
/// refused beyond 60 s of the hub's. A phone two minutes fast shows "Connected",
/// then "No response", and would otherwise fail over to a standby hub that
/// refuses it the same way and count the primary as failed.
@Riverpod(keepAlive: true)
class ClockSkewNotifier extends _$ClockSkewNotifier with AppLogger implements ClockEvidenceSink {
  final _tracker = ClockTracker();

  /// Monotonic time for the tracker: the wall clock is the thing under suspicion.
  final _uptime = Stopwatch()..start();

  /// A publish is waiting for the current Riverpod flush to finish.
  bool _publishQueued = false;

  @override
  ClockIssue? build() => _tracker.issue;

  @override
  void sample(ClockSample sample) => _apply(_tracker.sample(sample, _uptime.elapsed));

  @override
  void certificateDatesRejected() => _apply(_tracker.certificateDatesRejected(_uptime.elapsed));

  /// Hides the warning until the clock is right again; a later wrong clock
  /// shows it again.
  void dismiss() {
    _tracker.dismiss();
    _queuePublish();
  }

  /// For the hub-reachability ladder, which has just watched the tunnel fail:
  /// whether a wrong device clock explains it, on recent evidence. When it
  /// does, the failure is local and must not be counted or acted on as a hub
  /// fault. Synchronous, so a caller evaluates it after its last await.
  bool explainsDeadTunnel() => _tracker.explains(_uptime.elapsed);

  /// Whether the clock is unread, or was last read too long ago to say
  /// anything about now.
  bool get needsReading => !_tracker.hasFreshReading(_uptime.elapsed);

  void _apply(ClockEffect effect) {
    switch (effect) {
      case ClockEffect.raised:
        final skew = _tracker.issue?.skew;
        loggy.warning(
          skew == null
              ? "a server certificate was dated as expired or not yet valid; the device date is wrong"
              : "the device clock is ${skew.inSeconds.abs()} s ${skew.isNegative ? "behind" : "ahead of"} our servers; "
                    "the hubs refuse handshakes more than 60 s off",
        );
      case ClockEffect.cleared:
        loggy.info("the device clock agrees with our servers again");
      case ClockEffect.none:
        break;
    }
    _queuePublish();
  }

  /// The tracker changes at once, so [explainsDeadTunnel] sees a sample the
  /// moment it lands; the state the home page watches follows after the
  /// current Riverpod flush. Samples arrive from HTTP completions that can run
  /// inside one, and changing state there is the "Concurrent modification
  /// during iteration" crash LocalRoutingNotifier documents.
  void _queuePublish() {
    if (_publishQueued) return;
    _publishQueued = true;
    scheduleMicrotask(() {
      _publishQueued = false;
      final issue = _tracker.issue;
      // By value: an unchanged warning must not rebuild the banner.
      if (state != issue) state = issue;
    });
  }
}
