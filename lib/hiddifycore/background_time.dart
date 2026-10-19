import 'dart:async';

import 'package:hiddify/utils/custom_loggers.dart';

/// Keeps the app running until the work it holds has finished, where the
/// platform would otherwise suspend it part-way.
///
/// iOS suspends an app seconds after it leaves the screen, and a core start the
/// app drives is not finished when the tunnel comes up: the packet-tunnel
/// extension then waits for the app to send the configuration over gRPC. A user
/// who left in that gap had a VPN with nothing behind it until they came back
/// (2026-10-19 failover test: 17:36:03 to 17:36:18).
///
/// Holds nest. Only the first one in asks the platform, and only the last one
/// out releases it, so a failover holding time around its stop, start and probe
/// can call a start that holds time of its own.
///
/// Asking can fail (an older Runner without the method, a refusal) and must
/// never stop the work: that would turn a missing grace period into a failed
/// connect. Failures are logged and the body runs regardless.
class BackgroundTime with InfraLogger {
  BackgroundTime({required Future<void> Function() begin, required Future<void> Function() end})
    : _begin = begin,
      _end = end;

  final Future<void> Function() _begin;
  final Future<void> Function() _end;
  int _holds = 0;

  Future<T> hold<T>(Future<T> Function() body) async {
    if (_holds++ == 0) await _guard("begin", _begin);
    try {
      return await body();
    } finally {
      if (--_holds == 0) await _guard("end", _end);
    }
  }

  Future<void> _guard(String step, Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      loggy.warning("could not $step background time (${e.runtimeType})");
    }
  }
}
