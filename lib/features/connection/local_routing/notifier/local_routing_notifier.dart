import 'dart:async';

import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/connection/local_routing/data/egress_routing_probe.dart';
import 'package:hiddify/features/connection/local_routing/model/local_routing_tracker.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'local_routing_notifier.g.dart';

/// How often the warning re-reads the adapter while it is up, so it clears
/// within seconds of the user turning the setting off.
const localRoutingRecheckInterval = Duration(seconds: 5);

/// The "IP routing is on" warning (Windows only): null when there is nothing
/// to say. The rules are [LocalRoutingTracker]'s; this wires them to the app.
///
/// Driven by the same location result the orb shows ([activeProxyNotifierProvider],
/// which already re-subscribes across core restarts), not by a stream of its
/// own.
@Riverpod(keepAlive: true)
class LocalRoutingNotifier extends _$LocalRoutingNotifier with AppLogger {
  LocalRoutingTracker? _tracker;
  Timer? _recheck;

  @override
  LocalRoutingIssue? build() {
    if (!PlatformUtils.isWindows) return null;
    final probe = ref.watch(egressRoutingProbeProvider);
    _tracker = LocalRoutingTracker(probe.read);
    ref.onDispose(_stopRecheck);
    ref.listen(connectionNotifierProvider, (_, _) => _update());
    ref.listen(accountStateNotifierProvider, (_, _) => _update());
    ref.listen(activeProxyNotifierProvider, (_, _) => _update());
    return null;
  }

  /// Hides the warning until the issue clears; it comes back on a later one.
  void dismiss() {
    _tracker?.dismiss();
    if (state != _tracker?.issue) state = _tracker?.issue;
  }

  /// For the hub-reachability ladder, which has just watched the tunnel fail:
  /// whether IP routing on the egress adapter explains it. When it does, the
  /// failure is local and must not be counted or acted on as a hub fault.
  /// Synchronous, so a caller evaluates it after its last await.
  bool explainsDeadTunnel() {
    final tracker = _tracker;
    if (tracker == null) return false;
    final result = tracker.explain();
    _apply(result.effect);
    return result.explains;
  }

  void _update() {
    final tracker = _tracker;
    if (tracker == null) return;
    _apply(
      tracker.update((
        connected: ref.read(connectionNotifierProvider).valueOrNull is Connected,
        accountBlocked: ref.read(accountStateNotifierProvider).blocksConnect,
        delay: ref.read(activeProxyNotifierProvider).valueOrNull?.urlTestDelay ?? 0,
      )),
    );
  }

  void _apply(LocalRoutingEffect effect) {
    final issue = _tracker?.issue;
    switch (effect) {
      case LocalRoutingEffect.raised:
        loggy.warning("${issue?.routing}: the tunnel carries nothing because IP routing is on for this adapter");
        _startRecheck();
      case LocalRoutingEffect.solved:
        loggy.info("IP routing is off again on the egress adapter; re-testing the location");
        _stopRecheck();
        unawaited(_retest());
      case LocalRoutingEffect.cleared:
        _stopRecheck();
      case LocalRoutingEffect.none:
        break;
    }
    // By value: every re-check builds a new issue, and an unchanged one must
    // not rebuild the banner every five seconds.
    if (state != issue) state = issue;
  }

  void _startRecheck() {
    _recheck?.cancel();
    _recheck = Timer.periodic(localRoutingRecheckInterval, (_) {
      final tracker = _tracker;
      if (tracker != null) _apply(tracker.recheck());
    });
  }

  void _stopRecheck() {
    _recheck?.cancel();
    _recheck = null;
  }

  /// Failed locations are otherwise re-tested only on the core's 20–40 minute
  /// sweep, so the home page would keep showing a timeout for a tunnel that
  /// works again. "" is the active group, as the location page uses it.
  Future<void> _retest() async {
    final result = await ref.read(proxyRepositoryProvider).urlTest("").run();
    result.match((failure) => loggy.info("could not re-test the location after IP routing cleared", failure), (_) {});
  }
}
