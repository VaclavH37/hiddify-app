import 'package:hiddify/features/profile/model/account_envelope.dart';

/// What a verify 200 says about the account (the backend's recommendations,
/// §3). A 200 means the store answered and the backend applied that answer,
/// including "this subscription has ended", so the screen follows
/// `account_status` and never a missing link.
///
/// The fields ship with a later backend deployment; until then the status is
/// absent and [VerifyUnknown] keeps today's behaviour. Google's verify returns
/// the same fields.
sealed class VerifyVerdict {
  const VerifyVerdict();

  /// Parses a verify body. Never logs it: it can carry the subscription link,
  /// which is the credential.
  static VerifyVerdict parse(Map<String, dynamic> body) {
    final link = switch (body['subscription_url']) {
      final String s when s.isNotEmpty => s,
      _ => null,
    };
    final status = switch (body['account_status']) {
      final String s => s.trim().toLowerCase(),
      _ => '',
    };
    // Absent: the link could not be built in time, and the purchase may well
    // be active. The one case where "activating" is honest.
    if (status.isEmpty) return VerifyUnknown(link);
    return switch (status) {
      'active' => VerifyActive(link),
      // Everything below means nothing was granted. The backend confirmed
      // (2026-09-18) that a live purchase only ever answers `active` or no
      // field at all; any other stored state is reported only when the
      // verified subscription has ALREADY ENDED. So none of these may reach
      // the fallback link fetch — it would 403 and land the user on
      // "activating… tap Restore" for a purchase that granted nothing.
      'expired' || 'pending_payment' => VerifyEnded(StoreStatus.parse(body['store_status'])),
      'pending_verification' => const VerifyNotEligible(),
      'pending_activation' => const VerifyPending(),
      _ => VerifyUnavailable(_middlewareCode(status)),
    };
  }

  /// The verify body names an account state; the middleware's verdicts name
  /// the same states as codes, and the post-auth screens pick their copy by
  /// those codes. One vocabulary on the client.
  static String _middlewareCode(String status) => switch (status) {
    'suspended' => 'ACCOUNT_SUSPENDED',
    'deactivated' => 'ACCOUNT_DEACTIVATED',
    'self_deleted' || 'deleted' => 'ACCOUNT_DELETED',
    _ => status.toUpperCase(),
  };
}

/// Access granted. [link] is the renewed subscription when the backend had it
/// ready in time; otherwise it is fetched.
final class VerifyActive extends VerifyVerdict {
  const VerifyActive(this.link);

  final String? link;
}

/// The subscription has ended; nothing was granted. [storeStatus] is why,
/// when the store said.
final class VerifyEnded extends VerifyVerdict {
  const VerifyEnded(this.storeStatus);

  final StoreStatus storeStatus;
}

/// The account cannot receive access, whatever was bought. [code] is in the
/// middleware's vocabulary (`ACCOUNT_SUSPENDED`, …).
final class VerifyUnavailable extends VerifyVerdict {
  const VerifyUnavailable(this.code);

  final String code;
}

/// Nothing was granted, and the account's email is not verified yet. (A live
/// purchase on such an account is a `403 INELIGIBLE`, never a 200.)
final class VerifyNotEligible extends VerifyVerdict {
  const VerifyNotEligible();
}

/// Nothing was granted, and the account is waiting on a web payment to
/// settle. No store purchase passes through that window.
final class VerifyPending extends VerifyVerdict {
  const VerifyPending();
}

/// The backend did not say: a build from before the field shipped, or a link
/// that was not ready in time.
final class VerifyUnknown extends VerifyVerdict {
  const VerifyUnknown(this.link);

  final String? link;
}

/// Why the store ended a subscription, in the words the middleware also uses
/// for `subscription-store-status`.
enum StoreStatus {
  billingRetry,
  expired,
  revoked,
  unknown;

  static StoreStatus parse(Object? raw) => switch (raw) {
    AccountExpiry.storeBillingRetry => billingRetry,
    AccountExpiry.storeExpired => expired,
    AccountExpiry.storeRevoked => revoked,
    _ => unknown,
  };
}
