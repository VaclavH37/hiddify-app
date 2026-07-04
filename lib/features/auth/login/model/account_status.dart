/// Account lifecycle status returned by the auth API (`account_status` on the
/// login response and `status` on `GET /account`).
///
/// Login succeeds (a session is issued) for [active], [pendingPayment],
/// [pendingActivation], and [expired] — an expired plan can still sign in to
/// renew. [pendingVerification], [suspended], and [deactivated] are rejected at
/// login with a dedicated error code (see §8).
enum AccountStatus {
  active,
  pendingPayment,
  pendingActivation,
  pendingVerification,
  expired,
  suspended,
  deactivated,
  unknown;

  static AccountStatus fromApi(String? value) {
    switch (value) {
      case 'active':
        return AccountStatus.active;
      case 'pending_payment':
        return AccountStatus.pendingPayment;
      case 'pending_activation':
        return AccountStatus.pendingActivation;
      case 'pending_verification':
        return AccountStatus.pendingVerification;
      case 'expired':
        return AccountStatus.expired;
      case 'suspended':
        return AccountStatus.suspended;
      case 'deactivated':
        return AccountStatus.deactivated;
      default:
        return AccountStatus.unknown;
    }
  }
}
