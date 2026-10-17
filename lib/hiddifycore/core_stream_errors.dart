import 'package:grpc/grpc.dart';

/// How loudly a failed core stream is reported.
enum CoreStreamErrorLevel { debug, warning, error }

/// The severity a core stream failure actually warrants, by stream key ("bg…"
/// or "fg…") and error.
///
/// `UNAVAILABLE` means nothing is listening on the port. For the BACKGROUND
/// core that is its normal resting state — it lives in the platform VPN
/// service and does not exist until the tunnel starts — and the unary path
/// has always treated it that way (see the `changeHiddifySettings` split).
/// The stream path did not, so every launch emitted a burst of ERROR lines
/// for a condition that is routine.
///
/// That is not cosmetic. A foreground core that failed to start produces the
/// SAME lines, so the one failure worth acting on was indistinguishable from
/// the one that is expected, and an iOS import bug hid behind it. Hence the
/// key check rather than a blanket demotion: `UNAVAILABLE` from the
/// foreground core stays an error, because there it is one.
///
/// An HTTP/2 connection reset is a warning. The http2 package (2.3.1) closes
/// the whole connection with a PROTOCOL_ERROR when the core finishes a stream
/// the app has just cancelled (HEADERS on a closed stream,
/// `stream_handler.dart`), and a core restart such as a failover makes that
/// likely. Every stream on the channel then fails with "HTTP/2 error:
/// Connection error: Connection is being forcefully terminated", and each is
/// reopened: the status stream by the next watchStatus, the log stream when
/// the core next starts or is set up.
CoreStreamErrorLevel coreStreamErrorLevel(String key, Object? error) {
  if (error is! GrpcError) return CoreStreamErrorLevel.error;
  if (key.startsWith("bg") && error.code == StatusCode.unavailable) return CoreStreamErrorLevel.debug;
  if (error.code == StatusCode.unknown && (error.message?.contains("HTTP/2 error") ?? false)) {
    return CoreStreamErrorLevel.warning;
  }
  return CoreStreamErrorLevel.error;
}
