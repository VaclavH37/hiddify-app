/// Outcome kinds the delete-account screen renders on a non-success result.
/// Mirrors the shape of `RegisterOutcome` / `LoginOutcome`.
enum DeleteAccountOutcome {
  /// `403 INVALID_PASSWORD` — the confirmation password was wrong. The only
  /// outcome the user can fix by retrying on this screen.
  invalidPassword,

  /// `401`, or no `session_token` on the device at all. The account API cannot
  /// identify the caller, so the screen falls back to its sign-in step.
  needsLogin,

  /// `429` — deletion is rate limited server-side. Retrying immediately will
  /// not help.
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
