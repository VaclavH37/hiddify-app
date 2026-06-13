/// Typed error for the account/auth API.
///
/// Per the integration guide §5, non-2xx responses are JSON. Most are
/// `{"error":"<message>"}`; some carry a machine-readable
/// `{"error":"...","code":"<CODE>"}`. Callers MUST branch on [code] (and
/// [status]) — never on the human-readable [message] string, which is for
/// logging/debugging only and is never shown verbatim to the user.
class AuthApiException implements Exception {
  const AuthApiException({required this.status, this.code, required this.message, this.retryAfter});

  /// HTTP status code (0 for transport-level failures like timeout/no-route).
  final int status;

  /// Machine-readable code when present, e.g. `EMAIL_NOT_VERIFIED`,
  /// `REAUTH_REQUIRED`, `ACCOUNT_SUSPENDED`, `CRYPTOLINK_UNAVAILABLE`.
  final String? code;

  /// Raw server `error` text or a transport description. Not user-facing.
  final String message;

  /// Parsed `Retry-After` (seconds) when the server sent one (503 path).
  final Duration? retryAfter;

  /// Transport-level failure (connection refused, timeout, no route) — the
  /// host was unreachable. Distinct from an HTTP error response.
  bool get isUnreachable => status == 0;

  /// 0-status sentinel for an unreachable host.
  factory AuthApiException.unreachable(String message) => AuthApiException(status: 0, message: message);

  @override
  String toString() => 'AuthApiException(status: $status, code: $code)';
}
