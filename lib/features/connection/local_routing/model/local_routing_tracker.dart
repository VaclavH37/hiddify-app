import 'package:flutter/foundation.dart';
import 'package:hiddify/features/connection/local_routing/model/egress_routing.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';

/// The warning the home page shows: the adapter, and whether the user closed it.
@immutable
class LocalRoutingIssue {
  const LocalRoutingIssue({required this.routing, this.dismissed = false});

  final EgressRouting routing;
  final bool dismissed;

  @override
  bool operator ==(Object other) =>
      other is LocalRoutingIssue && other.routing == routing && other.dismissed == dismissed;

  @override
  int get hashCode => Object.hash(routing, dismissed);
}

/// What the notifier has to do besides publishing the tracker's [LocalRoutingTracker.issue].
enum LocalRoutingEffect {
  none,

  /// A new issue: log it, start re-checking.
  raised,

  /// The issue went away without the setting being seen off (a disconnect,
  /// traffic flowing, an account verdict): stop re-checking.
  cleared,

  /// The setting was seen off while connected: stop re-checking and have the
  /// core re-test the location now, so the home page shows a latency instead
  /// of the stale timeout until the next sweep 20–40 minutes away.
  solved,
}

/// Signals the warning depends on, as of one moment.
typedef LocalRoutingSignals = ({bool connected, bool accountBlocked, int delay});

/// The rules behind the "IP routing is on" warning, free of Riverpod and FFI so
/// each one is a plain test.
///
/// - The warning needs BOTH a dead tunnel (the location's URL test timed out)
///   and a live probe that finds forwarding on. A PC where forwarding is on and
///   traffic flows never sees it, and a replayed timeout from the previous
///   session never raises it on its own.
/// - It clears on a disconnect, on a live latency, on an account verdict
///   (which explains the timeouts itself), or on a probe that finds the
///   setting off.
/// - A dismissal lasts as long as the issue does.
class LocalRoutingTracker {
  LocalRoutingTracker(this._probe);

  final EgressRouting? Function() _probe;

  LocalRoutingIssue? _issue;
  LocalRoutingIssue? get issue => _issue;

  LocalRoutingEffect update(LocalRoutingSignals signals) {
    if (!signals.connected || signals.accountBlocked) return _clear(solved: false);
    // Not measured yet: nothing to say either way.
    if (signals.delay <= 0) return LocalRoutingEffect.none;
    // A live latency: whatever was wrong, traffic flows.
    if (signals.delay < hubUrlTestTimeout) return _clear(solved: false);
    return _probeNow().effect;
  }

  /// The periodic re-check while an issue is up.
  LocalRoutingEffect recheck() => _issue == null ? LocalRoutingEffect.none : _probeNow().effect;

  /// For the hub-reachability ladder, which has just watched the tunnel fail:
  /// whether the egress adapter explains it.
  ({bool explains, LocalRoutingEffect effect}) explain() => _probeNow();

  void dismiss() {
    final issue = _issue;
    if (issue != null) _issue = LocalRoutingIssue(routing: issue.routing, dismissed: true);
  }

  ({bool explains, LocalRoutingEffect effect}) _probeNow() {
    final routing = _probe();
    if (routing != null && routing.blocksTunnel) {
      final raised = _issue == null;
      _issue = LocalRoutingIssue(routing: routing, dismissed: _issue?.dismissed ?? false);
      return (explains: true, effect: raised ? LocalRoutingEffect.raised : LocalRoutingEffect.none);
    }
    return (explains: false, effect: _clear(solved: true));
  }

  LocalRoutingEffect _clear({required bool solved}) {
    if (_issue == null) return LocalRoutingEffect.none;
    _issue = null;
    return solved ? LocalRoutingEffect.solved : LocalRoutingEffect.cleared;
  }
}
