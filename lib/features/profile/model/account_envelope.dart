import 'dart:convert';

import 'package:hiddify/features/auth/model/payment_provider.dart';
import 'package:meta/meta.dart';

/// The middleware's account-status envelope: an HTTP 200 whose JSON body
/// carries `error_code` instead of a sing-box config
/// (ACCOUNT-REFRESH-MW-HANDOVER.md §4, §6, §7).
///
/// | `error_code` | Meaning |
/// |---|---|
/// | 4010 | token `exp` passed; renewed when `new-url`/`new_url` is present |
/// | 4011 | account expired while the token was still valid (store refund, early lapse) |
/// | 4012 | account unavailable: not renewable |
///
/// Only the body decides. The `subscription-*` headers repeat the same fields
/// and are read as fallbacks; the covert 404 never reaches this parser because
/// dio rejects non-2xx before the body is inspected, which is what §8 requires.
sealed class AccountEnvelope {
  const AccountEnvelope();

  /// The code the first handover named transient. Since the Worker's reply a
  /// retryable 4012 is keyed on `retry_after` instead (§4.3 there); this name
  /// match stays as the fallback for a Worker that has not deployed that yet.
  static const transientCode = 'SUBSCRIPTION_UNAVAILABLE';

  static bool isTransientCode(String code) => code == transientCode;

  /// `retry_after` is accepted from 1 s to a day, as the Worker itself
  /// enforces; anything else is treated as absent.
  static const maxRetryAfter = Duration(days: 1);

  /// Parses [body] with [headers] as fallbacks. Null when the body is not an
  /// account-status envelope: a config, a non-JSON body, or an `error_code`
  /// this contract does not define (the covert 404's `404`, for one) all fall
  /// through to the ordinary config path.
  static AccountEnvelope? parse(String body, Map<String, dynamic> headers) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body.trim());
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final errorCode = _int(decoded['error_code']);
    if (errorCode == null) return null;

    final verdict = _string(decoded['code']) ?? _header(headers, 'subscription-account-code');
    switch (errorCode) {
      case 4010:
        // Legacy form (no backend verdict) and the renewed form both lack a
        // `code`; the caller follows `newUrl` before treating this as expired.
        if (verdict == null) {
          return AccountEnvelopeExpired(
            details: _expiry(decoded, headers),
            legacy: true,
            newUrl: _string(decoded['new_url']),
          );
        }
        if (verdict == 'ACCOUNT_EXPIRED') {
          return AccountEnvelopeExpired(details: _expiry(decoded, headers), newUrl: _string(decoded['new_url']));
        }
        return _unavailable(verdict, decoded, headers);
      case 4011:
        return AccountEnvelopeExpired(details: _expiry(decoded, headers));
      case 4012:
        return _unavailable(verdict ?? AccountEnvelopeUnavailable.unknownCode, decoded, headers);
      default:
        return null;
    }
  }

  static AccountExpiry _expiry(Map<dynamic, dynamic> body, Map<String, dynamic> headers) => AccountExpiry(
    paymentProvider: _string(body['payment_provider']) ?? _header(headers, 'subscription-payment-provider'),
    billingPeriod: _string(body['billing_period']) ?? _header(headers, 'subscription-billing-period'),
    expiresAt: _epoch(_int(body['expires_at']) ?? _int(_header(headers, 'subscription-expire-date'))),
    manageUrl: _https(_string(body['manage_url']) ?? _header(headers, 'subscription-manage-url')),
    accountId: _accountId(body, headers),
    storeStatus: _string(body['store_status']) ?? _header(headers, 'subscription-store-status'),
    endedAt: _epoch(_int(body['ended_at']) ?? _int(_header(headers, 'subscription-ended-at'))),
    renewUrl: _https(_string(body['renew_url']) ?? _header(headers, 'subscription-renew-url')),
  );

  static AccountEnvelopeUnavailable _unavailable(
    String code,
    Map<dynamic, dynamic> body,
    Map<String, dynamic> headers,
  ) => AccountEnvelopeUnavailable(
    code: code,
    retryAfter: _retryAfter(_int(body['retry_after']) ?? _int(_header(headers, 'subscription-retry-after'))),
    accountId: _accountId(body, headers),
  );

  static String? _accountId(Map<dynamic, dynamic> body, Map<String, dynamic> headers) =>
      _string(body['account_id']) ?? _header(headers, 'subscription-account-id');

  static Duration? _retryAfter(int? seconds) {
    if (seconds == null || seconds < 1) return null;
    final value = Duration(seconds: seconds);
    return value > maxRetryAfter ? null : value;
  }

  static int? _int(Object? value) => switch (value) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Header values arrive as a String, or a List when dio saw the name more
  /// than once; the first value wins, matching `extractRotation`.
  static String? _header(Map<String, dynamic> headers, String name) => switch (headers[name]) {
    final String s => _string(s),
    final List l when l.isNotEmpty => _string(l.first?.toString()),
    _ => null,
  };

  /// Unix seconds per the contract. A value past the year 5000 can only be
  /// milliseconds, so it is scaled rather than rendered as a 55,000-year date.
  static DateTime? _epoch(int? value) {
    if (value == null || value <= 0) return null;
    final seconds = value > 100000000000 ? value ~/ 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// The renew link is opened as received (there is no host allow-list, by
  /// decision), so the one check is that it is an https URL at all.
  static Uri? _https(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? uri : null;
  }
}

/// 4010 or 4011: renew to continue. [newUrl] is the body's `new_url` on a
/// renewed 4010 — the header form is read first by the parser, this is the
/// fallback. [legacy] marks a 4010 with no backend verdict.
@immutable
class AccountEnvelopeExpired extends AccountEnvelope {
  const AccountEnvelopeExpired({required this.details, this.legacy = false, this.newUrl});

  final AccountExpiry details;
  final bool legacy;
  final String? newUrl;
}

/// 4012, or a 4010 whose verdict is something other than expired. Never
/// renewable; an unrecognised [code] is "unavailable", not a client error (§7).
@immutable
class AccountEnvelopeUnavailable extends AccountEnvelope {
  const AccountEnvelopeUnavailable({required this.code, this.retryAfter, this.accountId});

  static const unknownCode = 'UNKNOWN';

  final String code;

  /// Present when the Worker says this state can clear without the user
  /// paying (its reply, §4.3): `SUBSCRIPTION_UNAVAILABLE`, `ACCOUNT_PENDING`,
  /// and any retryable code added later. Never on suspended, closed, deleted
  /// or unknown accounts.
  final Duration? retryAfter;

  /// The token's `uid`. Identifies the user across rotations; never logged.
  final String? accountId;

  /// A temporary state, not a verdict: the refresh loop backs off for
  /// [retryAfter] and records nothing. Keyed on `retry_after`, with the one
  /// code the first handover named as the pre-deploy fallback.
  bool get transient => retryAfter != null || AccountEnvelope.isTransientCode(code);
}

/// What the renewal screen needs to know about a lapsed plan. Every field is
/// optional: the legacy 4010 and the panel-only 4011 carry none of them.
@immutable
class AccountExpiry {
  const AccountExpiry({
    this.paymentProvider,
    this.billingPeriod,
    this.expiresAt,
    this.manageUrl,
    this.accountId,
    this.storeStatus,
    this.endedAt,
    this.renewUrl,
  });

  static const none = AccountExpiry();

  /// `store_status` values the Worker passes through from the backend
  /// (its reply, §5.3).
  static const storeBillingRetry = 'billing_retry';
  static const storeExpired = 'expired';
  static const storeRevoked = 'revoked';

  /// Why a store-billed plan ended: [storeBillingRetry], [storeExpired] or
  /// [storeRevoked]. Absent for web billing and trials, and until the backend
  /// ships it; anything unrecognised gets the generic copy.
  final String? storeStatus;

  /// When access ended, if earlier than [expiresAt] (`ended_at`): a refund or
  /// a revocation. Always in the past, so it can be rendered.
  final DateTime? endedAt;

  /// A per-user web checkout (`renew_url`), https only; web billing and trials,
  /// never store billing. Opened on desktop instead of the generic account
  /// page. Short-lived and a credential: never logged, never kept beyond the
  /// verdict it came with.
  final Uri? renewUrl;

  /// The token's `uid` (`account_id` / `subscription-account-id`). Compared
  /// as an exact string to a signed-in account's id once the backend confirms
  /// login returns the same string; until then read, kept, never enforced.
  /// Absent means unknown, never a mismatch. Never logged.
  final String? accountId;

  /// `app_store`, `google_play`, `nowpayments`, `guardarian`, `trial`, `admin`
  /// or a value this build has not heard of; only the store pair is matched.
  final String? paymentProvider;

  /// `monthly` / `quarterly` / `annual`; omitted for trials.
  final String? billingPeriod;

  /// End of the last paid period, UTC. Can be in the FUTURE on a 4011 (a store
  /// refund ends the account before its period does), so never derive
  /// "expires in N days" from it.
  final DateTime? expiresAt;

  /// The store's subscription centre for store-billed plans; absent otherwise.
  final Uri? manageUrl;

  bool get isStoreManaged => isStoreManagedProvider(paymentProvider);

  /// True only when the end date is known and already behind us.
  bool endedBefore(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  Map<String, Object?> toJson() => {
    'paymentProvider': paymentProvider,
    'billingPeriod': billingPeriod,
    'expiresAt': expiresAt == null ? null : expiresAt!.millisecondsSinceEpoch ~/ 1000,
    'manageUrl': manageUrl?.toString(),
    'accountId': accountId,
    'storeStatus': storeStatus,
    'endedAt': endedAt == null ? null : endedAt!.millisecondsSinceEpoch ~/ 1000,
    'renewUrl': renewUrl?.toString(),
  };

  factory AccountExpiry.fromJson(Map<String, Object?> json) => AccountExpiry(
    paymentProvider: AccountEnvelope._string(json['paymentProvider']),
    billingPeriod: AccountEnvelope._string(json['billingPeriod']),
    expiresAt: AccountEnvelope._epoch(AccountEnvelope._int(json['expiresAt'])),
    manageUrl: AccountEnvelope._https(AccountEnvelope._string(json['manageUrl'])),
    accountId: AccountEnvelope._string(json['accountId']),
    storeStatus: AccountEnvelope._string(json['storeStatus']),
    endedAt: AccountEnvelope._epoch(AccountEnvelope._int(json['endedAt'])),
    renewUrl: AccountEnvelope._https(AccountEnvelope._string(json['renewUrl'])),
  );

  @override
  bool operator ==(Object other) =>
      other is AccountExpiry &&
      other.paymentProvider == paymentProvider &&
      other.billingPeriod == billingPeriod &&
      other.expiresAt == expiresAt &&
      other.manageUrl == manageUrl &&
      other.accountId == accountId &&
      other.storeStatus == storeStatus &&
      other.endedAt == endedAt &&
      other.renewUrl == renewUrl;

  @override
  int get hashCode =>
      Object.hash(paymentProvider, billingPeriod, expiresAt, manageUrl, accountId, storeStatus, endedAt, renewUrl);

  // toString deliberately omits accountId and renewUrl: this string reaches
  // the log, and both identify or act for the user.

  @override
  String toString() =>
      'AccountExpiry($paymentProvider, $billingPeriod, ${expiresAt?.toIso8601String()}, ${manageUrl?.host})';
}
