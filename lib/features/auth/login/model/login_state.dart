/// Outcome kinds the login form renders. `pendingPayment`/`pendingActivation`
/// are informational (not failures) but, like the error variants, they halt the
/// flow and show a message — so they share the same surface.
enum LoginOutcome {
  invalidCredentials,
  emailNotVerified,
  accountSuspended,
  accountDeactivated,
  pendingPayment,
  pendingActivation,
  expired,
  verifyFailed,
  unreachable,

  /// Plan-transition re-auth only: the credentials are valid but belong to a
  /// different account than the subscription active on this device. Never
  /// occurs in the normal login flow (which passes no expected account).
  accountMismatch,

  /// The account's subscription cryptolink uses an envelope version this build
  /// has no handler for. The credentials are fine — the app is out of date
  /// (RAYN-LINK-SYMMETRIC-MIGRATION.md §10).
  updateRequired,
  generic,
}

enum LoginPhase { idle, submitting, outcome, success }

class LoginState {
  const LoginState({this.phase = LoginPhase.idle, this.outcome});

  final LoginPhase phase;
  final LoginOutcome? outcome;

  bool get isSubmitting => phase == LoginPhase.submitting;

  static const idle = LoginState();
  static const submitting = LoginState(phase: LoginPhase.submitting);
  static const success = LoginState(phase: LoginPhase.success);

  factory LoginState.fail(LoginOutcome outcome) => LoginState(phase: LoginPhase.outcome, outcome: outcome);
}
