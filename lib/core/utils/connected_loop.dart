import 'dart:async';

/// Runs [check] while connected: once after [firstDelay] when the connection
/// comes up, then again after whatever delay each run returns, until it goes
/// down. Disconnecting cancels the wait and calls [onStop], which aborts a run
/// in flight; a run that finishes after the disconnect schedules nothing. A
/// run that throws is tried again after [retryAfterFailure].
///
/// Shared by the rule-set updater and the Windows app updater: both fetch only
/// through the tunnel, so neither has anything to do while disconnected.
class ConnectedLoop {
  ConnectedLoop({required this.check, required this.firstDelay, required this.retryAfterFailure, this.onStop});

  final Future<Duration> Function() check;
  final Duration Function() firstDelay;
  final Duration retryAfterFailure;
  final void Function()? onStop;

  Timer? _timer;
  var _connected = false;

  void connected(bool value) {
    if (value == _connected) return;
    _connected = value;
    if (value) {
      _schedule(firstDelay());
    } else {
      stop();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    onStop?.call();
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _fire);
  }

  Future<void> _fire() async {
    _timer = null;
    if (!_connected) return;
    Duration next;
    try {
      next = await check();
    } catch (_) {
      next = retryAfterFailure;
    }
    if (_connected && _timer == null) _schedule(next);
  }
}
