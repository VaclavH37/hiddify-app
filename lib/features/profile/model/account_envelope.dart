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

  /// The single code the handover marks transient (§7): the next poll may
  /// succeed, so it is a failed refresh, not an account verdict.
  static const transientCode = 'SUBSCRIPTION_UNAVAILABLE';

  static bool isTransientCode(String code) => code == transientCode;

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
        return AccountEnvelopeUnavailable(code: verdict);
      case 4011:
        return AccountEnvelopeExpired(details: _expiry(decoded, headers));
      case 4012:
        return AccountEnvelopeUnavailable(code: verdict ?? AccountEnvelopeUnavailable.unknownCode);
      default:
        return null;
    }
  }

  static AccountExpiry _expiry(Map<dynamic, dynamic> body, Map<String, dynamic> headers) => AccountExpiry(
    paymentProvider: _string(body['payment_provider']) ?? _header(headers, 'subscription-payment-provider'),
    billingPeriod: _string(body['billing_period']) ?? _header(headers, 'subscription-billing-period'),
    expiresAt: _epoch(_int(body['expires_at']) ?? _int(_header(headers, 'subscription-expire-date'))),
    manageUrl: _https(_string(body['manage_url']) ?? _header(headers, 'subscription-manage-url')),
  );

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
  const AccountEnvelopeUnavailable({required this.code});

  static const unknownCode = 'UNKNOWN';

  final String code;

  bool get transient => AccountEnvelope.isTransientCode(code);
}

/// What the renewal screen needs to know about a lapsed plan. Every field is
/// optional: the legacy 4010 and the panel-only 4011 carry none of them.
@immutable
class AccountExpiry {
  const AccountExpiry({this.paymentProvider, this.billingPeriod, this.expiresAt, this.manageUrl});

  static const none = AccountExpiry();

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
  };

  factory AccountExpiry.fromJson(Map<String, Object?> json) => AccountExpiry(
    paymentProvider: AccountEnvelope._string(json['paymentProvider']),
    billingPeriod: AccountEnvelope._string(json['billingPeriod']),
    expiresAt: AccountEnvelope._epoch(AccountEnvelope._int(json['expiresAt'])),
    manageUrl: AccountEnvelope._https(AccountEnvelope._string(json['manageUrl'])),
  );

  @override
  bool operator ==(Object other) =>
      other is AccountExpiry &&
      other.paymentProvider == paymentProvider &&
      other.billingPeriod == billingPeriod &&
      other.expiresAt == expiresAt &&
      other.manageUrl == manageUrl;

  @override
  int get hashCode => Object.hash(paymentProvider, billingPeriod, expiresAt, manageUrl);

  @override
  String toString() =>
      'AccountExpiry($paymentProvider, $billingPeriod, ${expiresAt?.toIso8601String()}, ${manageUrl?.host})';
}
