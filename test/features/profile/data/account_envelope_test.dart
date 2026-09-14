import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';

/// Every body below is a capture from ACCOUNT-REFRESH-MW-HANDOVER.md §6–§8,
/// so a passing suite means the client reads exactly what the Worker sends.
void main() {
  const noHeaders = <String, dynamic>{};
  DateTime utc(int seconds) => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  AccountEnvelopeExpired expired(String body, [Map<String, dynamic> headers = noHeaders]) {
    final envelope = AccountEnvelope.parse(body, headers);
    expect(envelope, isA<AccountEnvelopeExpired>(), reason: body);
    return envelope! as AccountEnvelopeExpired;
  }

  AccountEnvelopeUnavailable unavailable(String body, [Map<String, dynamic> headers = noHeaders]) {
    final envelope = AccountEnvelope.parse(body, headers);
    expect(envelope, isA<AccountEnvelopeUnavailable>(), reason: body);
    return envelope! as AccountEnvelopeUnavailable;
  }

  group('not an envelope', () {
    test('a sing-box config', () {
      expect(AccountEnvelope.parse('{"outbounds":[],"dns":{}}', noHeaders), isNull);
    });

    test('non-JSON bodies', () {
      expect(AccountEnvelope.parse('', noHeaders), isNull);
      expect(AccountEnvelope.parse('vmess://abc', noHeaders), isNull);
      expect(AccountEnvelope.parse('not json at all', noHeaders), isNull);
      expect(AccountEnvelope.parse('[1,2]', noHeaders), isNull);
    });

    test('the covert 404 body is never an account verdict (§8)', () {
      expect(
        AccountEnvelope.parse('{"success":false,"error_code":404,"message":"Resource not found"}', noHeaders),
        isNull,
      );
    });

    test('an error_code outside the contract', () {
      expect(AccountEnvelope.parse('{"success":false,"error_code":4013,"code":"ACCOUNT_EXPIRED"}', noHeaders), isNull);
    });
  });

  group('4011 — account expired while the token was valid', () {
    test('App Store: provider, plan, end date and the renew link', () {
      final e = expired(
        '{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"message":"Subscription expired","expires_at":1791968400,"billing_period":"monthly", '
        '"payment_provider":"app_store","manage_url":"https://apps.apple.com/account/subscriptions"}',
      );
      expect(e.legacy, isFalse);
      expect(e.newUrl, isNull);
      expect(e.details.paymentProvider, 'app_store');
      expect(e.details.billingPeriod, 'monthly');
      expect(e.details.expiresAt, utc(1791968400));
      expect(e.details.manageUrl, Uri.parse('https://apps.apple.com/account/subscriptions'));
      expect(e.details.isStoreManaged, isTrue);
    });

    test('web billing: no renew link', () {
      final e = expired(
        '{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"message":"Subscription expired","expires_at":1789376400,"billing_period":"monthly", '
        '"payment_provider":"nowpayments"}',
      );
      expect(e.details.paymentProvider, 'nowpayments');
      expect(e.details.manageUrl, isNull);
      expect(e.details.isStoreManaged, isFalse);
    });

    test('trial: billing_period is omitted', () {
      final e = expired(
        '{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"message":"Subscription expired","expires_at":1789376400,"payment_provider":"trial"}',
      );
      expect(e.details.paymentProvider, 'trial');
      expect(e.details.billingPeriod, isNull);
    });

    test('panel-only verdict: no billing fields at all', () {
      final e = expired(
        '{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"message":"Subscription expired","expires_at":1789383527}',
      );
      expect(e.details.paymentProvider, isNull);
      expect(e.details.billingPeriod, isNull);
      expect(e.details.manageUrl, isNull);
      expect(e.details.expiresAt, utc(1789383527));
    });

    test('a verdict other than expired on a 4011 still reads as expired', () {
      expired('{"success":false,"error_code":4011,"code":"SOMETHING_NEW","expires_at":1789383527}');
    });

    test('a future end date is kept but never reads as ended', () {
      final e = expired('{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","expires_at":1791968400}');
      expect(e.details.endedBefore(utc(1791968399)), isFalse);
      expect(e.details.endedBefore(utc(1791968400)), isTrue);
    });
  });

  group('4010 — token expired', () {
    test('renewed: no verdict, the body new_url is exposed for the rotation', () {
      final e = expired(
        '{"success":false,"error_code":4010,"message":"Subscription token expired", '
        '"new_url":"rayn://import/RENEWED","billing_period":"monthly","payment_provider":"app_store", '
        '"manage_url":"https://apps.apple.com/account/subscriptions"}',
      );
      expect(e.legacy, isTrue);
      expect(e.newUrl, 'rayn://import/RENEWED');
    });

    test('lapsed App Store: the same fields as a 4011', () {
      final e = expired(
        '{"success":false,"error_code":4010,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"message":"Subscription token expired","expires_at":1791968400,"billing_period":"monthly", '
        '"payment_provider":"app_store","manage_url":"https://apps.apple.com/account/subscriptions"}',
      );
      expect(e.legacy, isFalse);
      expect(e.newUrl, isNull);
      expect(e.details.manageUrl, isNotNull);
    });

    test('lapsed web billing', () {
      final e = expired(
        '{"success":false,"error_code":4010,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"message":"Subscription token expired","expires_at":1789376400,"billing_period":"monthly", '
        '"payment_provider":"nowpayments"}',
      );
      expect(e.details.paymentProvider, 'nowpayments');
      expect(e.details.manageUrl, isNull);
    });

    test('legacy: no code and no fields is expired with nothing to renew with', () {
      final e = expired('{"success":false,"error_code":4010,"message":"Subscription token expired"}');
      expect(e.legacy, isTrue);
      expect(e.newUrl, isNull);
      expect(e.details, AccountExpiry.none);
    });

    test('a 4010 whose verdict is not expired is unavailable', () {
      final u = unavailable('{"success":false,"error_code":4010,"code":"ACCOUNT_SUSPENDED"}');
      expect(u.code, 'ACCOUNT_SUSPENDED');
    });
  });

  group('4012 — unavailable', () {
    test('suspended', () {
      final u = unavailable(
        '{"success":false,"error_code":4012,"code":"ACCOUNT_SUSPENDED","account_status":"suspended", '
        '"message":"Subscription unavailable"}',
      );
      expect(u.code, 'ACCOUNT_SUSPENDED');
      expect(u.transient, isFalse);
    });

    test('not found carries no account_status', () {
      final u = unavailable(
        '{"success":false,"error_code":4012,"code":"ACCOUNT_NOT_FOUND","message":"Subscription unavailable"}',
      );
      expect(u.code, 'ACCOUNT_NOT_FOUND');
    });

    test('an unrecognised code is unavailable, not a client error (§7)', () {
      expect(unavailable('{"success":false,"error_code":4012,"code":"ACCOUNT_FROZEN"}').code, 'ACCOUNT_FROZEN');
    });

    test('a missing code is UNKNOWN', () {
      expect(unavailable('{"success":false,"error_code":4012}').code, AccountEnvelopeUnavailable.unknownCode);
    });

    test('retry_after marks a 4012 transient, whatever its code (the Worker reply, §4.3)', () {
      final u = unavailable(
        '{"success":false,"error_code":4012,"code":"SUBSCRIPTION_UNAVAILABLE","account_status":"active", '
        '"account_id":"74550193-125b-48ca-9715-f25bb4c8490f","message":"Subscription unavailable","retry_after":900}',
      );
      expect(u.transient, isTrue);
      expect(u.retryAfter, const Duration(minutes: 15));
      expect(u.accountId, '74550193-125b-48ca-9715-f25bb4c8490f');
      expect(unavailable('{"success":false,"error_code":4012,"code":"ACCOUNT_PENDING","retry_after":300}').transient, isTrue);
      expect(unavailable('{"success":false,"error_code":4012,"code":"SOMETHING_NEW","retry_after":600}').transient, isTrue);
    });

    test('the legacy name still counts until every Worker sends retry_after; other codes never', () {
      final legacy = unavailable('{"success":false,"error_code":4012,"code":"SUBSCRIPTION_UNAVAILABLE"}');
      expect(legacy.transient, isTrue);
      expect(legacy.retryAfter, isNull);
      expect(unavailable('{"success":false,"error_code":4012,"code":"ACCOUNT_SUSPENDED"}').transient, isFalse);
      expect(unavailable('{"success":false,"error_code":4012,"code":"ACCOUNT_PENDING"}').transient, isFalse);
    });

    test('retry_after: header fallback, and only 1 s to a day is accepted', () {
      expect(
        unavailable('{"success":false,"error_code":4012,"code":"X"}', {'subscription-retry-after': '900'}).retryAfter,
        const Duration(minutes: 15),
      );
      for (final bad in ['0', '-5', '86401', 'abc']) {
        final u = unavailable('{"success":false,"error_code":4012,"code":"X","retry_after":"$bad"}');
        expect(u.retryAfter, isNull, reason: bad);
        expect(u.transient, isFalse, reason: bad);
      }
      expect(unavailable('{"success":false,"error_code":4012,"code":"X","retry_after":86400}').retryAfter, const Duration(days: 1));
    });
  });

  group('account id', () {
    test('body first, header fallback, never required', () {
      const body = '{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","expires_at":1789376400';
      expect(expired('$body,"account_id":"74550193-125b-48ca-9715-f25bb4c8490f"}').details.accountId, '74550193-125b-48ca-9715-f25bb4c8490f');
      expect(expired('$body}', {'subscription-account-id': 'from-header'}).details.accountId, 'from-header');
      expect(expired('$body}').details.accountId, isNull);
      expect(unavailable('{"success":false,"error_code":4012,"code":"ACCOUNT_SUSPENDED"}', {'subscription-account-id': 'h'}).accountId, 'h');
    });

    test('is not part of the printable form', () {
      const e = AccountExpiry(paymentProvider: 'app_store', accountId: '74550193-125b-48ca-9715-f25bb4c8490f');
      expect(e.toString(), isNot(contains('74550193')));
    });
  });

  group('header fallbacks', () {
    const headers = <String, dynamic>{
      'subscription-account-code': 'ACCOUNT_EXPIRED',
      'subscription-account-status': 'expired',
      'subscription-billing-period': 'monthly',
      'subscription-expire-date': '1791968400',
      'subscription-manage-url': 'https://apps.apple.com/account/subscriptions',
      'subscription-payment-provider': 'app_store',
    };

    test('headers fill in what the body omits', () {
      final e = expired('{"success":false,"error_code":4011,"message":"Subscription expired"}', headers);
      expect(e.details.paymentProvider, 'app_store');
      expect(e.details.billingPeriod, 'monthly');
      expect(e.details.expiresAt, utc(1791968400));
      expect(e.details.manageUrl, Uri.parse('https://apps.apple.com/account/subscriptions'));
    });

    test('the body wins over the headers', () {
      final e = expired(
        '{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","payment_provider":"nowpayments","expires_at":1789376400}',
        headers,
      );
      expect(e.details.paymentProvider, 'nowpayments');
      expect(e.details.expiresAt, utc(1789376400));
    });

    test('a multi-valued header takes the first value', () {
      final e = expired('{"success":false,"error_code":4011}', {
        'subscription-payment-provider': ['trial', 'app_store'],
      });
      expect(e.details.paymentProvider, 'trial');
    });

    test('subscription-account-code stands in for a missing body code on a 4010', () {
      final e = expired('{"success":false,"error_code":4010}', {'subscription-account-code': 'ACCOUNT_EXPIRED'});
      expect(e.legacy, isFalse);
      final u = unavailable('{"success":false,"error_code":4010}', {'subscription-account-code': 'ACCOUNT_DELETED'});
      expect(u.code, 'ACCOUNT_DELETED');
    });
  });

  group('field hygiene', () {
    test('error_code as a numeric string is accepted', () {
      expired('{"success":false,"error_code":"4011","code":"ACCOUNT_EXPIRED"}');
    });

    test('expires_at in milliseconds is scaled back to seconds', () {
      final e = expired('{"success":false,"error_code":4011,"expires_at":1791968400000}');
      expect(e.details.expiresAt, utc(1791968400));
    });

    test('a zero or negative expires_at is absent', () {
      expect(expired('{"success":false,"error_code":4011,"expires_at":0}').details.expiresAt, isNull);
      expect(expired('{"success":false,"error_code":4011,"expires_at":-5}').details.expiresAt, isNull);
    });

    test('a non-https manage_url is dropped', () {
      final e = expired('{"success":false,"error_code":4011,"manage_url":"http://apps.apple.com/x"}');
      expect(e.details.manageUrl, isNull);
      expect(
        expired('{"success":false,"error_code":4011,"manage_url":"javascript:alert(1)"}').details.manageUrl,
        isNull,
      );
    });

    test('blank strings are absent', () {
      final e = expired('{"success":false,"error_code":4011,"billing_period":"   ","payment_provider":""}');
      expect(e.details.billingPeriod, isNull);
      expect(e.details.paymentProvider, isNull);
    });
  });

  group('backend-pending fields (the Worker reply, §5)', () {
    test('an App Store refund: store_status, ended_at in the past, expires_at still in the future', () {
      final e = expired(
        '{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"store_status":"revoked","account_id":"74550193-125b-48ca-9715-f25bb4c8490f", '
        '"message":"Subscription expired","expires_at":1791968400,"ended_at":1789041600, '
        '"billing_period":"monthly","payment_provider":"app_store", '
        '"manage_url":"https://apps.apple.com/account/subscriptions"}',
      );
      expect(e.details.storeStatus, AccountExpiry.storeRevoked);
      expect(e.details.endedAt, utc(1789041600));
      expect(e.details.expiresAt, utc(1791968400));
      expect(e.details.endedBefore(utc(1789041601)), isFalse, reason: 'endedBefore reads expires_at only');
      expect(e.details.renewUrl, isNull);
    });

    test('web billing lapsed: renew_url, no manage_url', () {
      final e = expired(
        '{"success":false,"error_code":4010,"code":"ACCOUNT_EXPIRED","account_status":"expired", '
        '"account_id":"74550193-125b-48ca-9715-f25bb4c8490f","message":"Subscription token expired", '
        '"expires_at":1789376400,"billing_period":"monthly","payment_provider":"nowpayments", '
        '"renew_url":"https://checkout.example.invalid/renew/7f3c9a2e"}',
      );
      expect(e.details.renewUrl, Uri.parse('https://checkout.example.invalid/renew/7f3c9a2e'));
      expect(e.details.manageUrl, isNull);
      expect(e.details.storeStatus, isNull);
      expect(e.details.endedAt, isNull);
    });

    test('header fallbacks; renew_url must be https', () {
      final e = expired('{"success":false,"error_code":4011,"code":"ACCOUNT_EXPIRED"}', {
        'subscription-store-status': 'billing_retry',
        'subscription-ended-at': '1789041600',
        'subscription-renew-url': 'https://checkout.example.invalid/r/1',
      });
      expect(e.details.storeStatus, AccountExpiry.storeBillingRetry);
      expect(e.details.endedAt, utc(1789041600));
      expect(e.details.renewUrl, Uri.parse('https://checkout.example.invalid/r/1'));
      expect(
        expired('{"success":false,"error_code":4011,"renew_url":"http://checkout.example.invalid/r/1"}').details.renewUrl,
        isNull,
      );
    });

    test('an unrecognised store_status is kept as sent; the screen shows generic copy for it', () {
      expect(expired('{"success":false,"error_code":4011,"store_status":"grace"}').details.storeStatus, 'grace');
    });

    test('renew_url is not part of the printable form', () {
      final e = AccountExpiry(renewUrl: Uri.parse('https://checkout.example.invalid/renew/7f3c9a2e'));
      expect(e.toString(), isNot(contains('7f3c9a2e')));
    });
  });

  group('AccountExpiry json', () {
    test('round-trips every field', () {
      final original = AccountExpiry(
        paymentProvider: 'google_play',
        billingPeriod: 'annual',
        expiresAt: utc(1791968400),
        manageUrl: Uri.parse(
          'https://play.google.com/store/account/subscriptions?sku=rayn_premium_monthly&package=com.raynlabs.app',
        ),
        accountId: '74550193-125b-48ca-9715-f25bb4c8490f',
        storeStatus: AccountExpiry.storeRevoked,
        endedAt: utc(1789041600),
        renewUrl: Uri.parse('https://checkout.example.invalid/renew/7f3c9a2e'),
      );
      expect(AccountExpiry.fromJson(original.toJson()), original);
    });

    test('none round-trips as none', () {
      expect(AccountExpiry.fromJson(AccountExpiry.none.toJson()), AccountExpiry.none);
    });
  });
}
