/// Outcome kinds the delete-account screen renders on a non-success result.
/// Mirrors the shape of `RegisterOutcome` / `LoginOutcome`.
enum DeleteAccountOutcome {
  /// `401 INVALID_CREDENTIALS` — the confirmation password was wrong. The only
  /// outcome the user can fix by retrying on this screen.
  ///
  /// Note the status: a wrong password is a 401, the same status as a dead
  /// session, and the two are told apart only by the code.
  invalidPassword,

  /// `401`, or no `session_token` on the device at all. The account API cannot
  /// identify the caller, so the screen falls back to its sign-in step.
  needsLogin,

  /// `403 ACCOUNT_LOCKED` — an admin has the account under investigation.
  /// Unrecoverable from this screen no matter how correct the password is, so
  /// it must never be reported as a password failure.
  accountLocked,

  /// `409 PAYMENT_IN_FLIGHT` — a crypto/fiat payment is still settling, and the
  /// backend refuses deletion until it lands so a settlement cannot arrive for
  /// an account that no longer exists. Self-clearing, retryable in about an
  /// hour. Store subscriptions are excluded from this check by design, so it
  /// can never block an App Store subscriber (guideline 5.1.1(v)).
  paymentInFlight,

  /// `429` — deletion is rate limited server-side (5 per IP per hour, shared
  /// with `/forgot-password`). Retrying immediately will not help.
  rateLimited,

  /// Transport failure: the account host could not be reached.
  unreachable,

  /// Anything else, including `5xx`.
  generic,
}

enum DeleteAccountPhase { idle, deleting, outcome, success }

class DeleteAccountState {
  const DeleteAccountState({this.phase = DeleteAccountPhase.idle, this.outcome});

  final DeleteAccountPhase phase;
  final DeleteAccountOutcome? outcome;

  bool get isSubmitting => phase == DeleteAccountPhase.deleting;

  static const idle = DeleteAccountState();
  static const deleting = DeleteAccountState(phase: DeleteAccountPhase.deleting);

  /// Terminal success: the account is gone server-side. The local wipe that
  /// follows is best-effort and does not change this.
  static const success = DeleteAccountState(phase: DeleteAccountPhase.success);

  factory DeleteAccountState.fail(DeleteAccountOutcome outcome) =>
      DeleteAccountState(phase: DeleteAccountPhase.outcome, outcome: outcome);
}
