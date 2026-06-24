/// Outcome kinds the registration form renders on a non-success result.
/// Mirrors the shape of `LoginOutcome`.
enum RegisterOutcome { validationError, tooManyRequests, verifyFailed, unreachable, generic }

enum RegisterPhase { idle, submitting, outcome, success }

class RegisterState {
  const RegisterState({this.phase = RegisterPhase.idle, this.outcome, this.serverMessage});

  final RegisterPhase phase;
  final RegisterOutcome? outcome;

  /// For a `400 validationError`: the server's human-readable message, shown
  /// inline (e.g. "password is too common", which the client can't pre-check).
  final String? serverMessage;

  bool get isSubmitting => phase == RegisterPhase.submitting;

  static const idle = RegisterState();
  static const submitting = RegisterState(phase: RegisterPhase.submitting);
  static const success = RegisterState(phase: RegisterPhase.success);

  factory RegisterState.fail(RegisterOutcome outcome, {String? serverMessage}) =>
      RegisterState(phase: RegisterPhase.outcome, outcome: outcome, serverMessage: serverMessage);
}
