/// How long to wait before reopening a core stream that ended.
///
/// The wait starts at [min] and doubles each time reopening fails again, up to
/// [max], so a core that stays unreachable is not retried, and its failure
/// logged, every couple of seconds. [reset] goes back to [min] once the stream
/// delivers again or the connection changes.
class ResubscribeBackoff {
  ResubscribeBackoff({this.min = const Duration(seconds: 2), this.max = const Duration(seconds: 30)}) : _next = min;

  final Duration min;
  final Duration max;
  Duration _next;

  /// The wait before this reopen. The one after it is twice as long, up to [max].
  Duration next() {
    final wait = _next;
    final doubled = _next * 2;
    _next = doubled < max ? doubled : max;
    return wait;
  }

  void reset() => _next = min;
}
