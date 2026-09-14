import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/model/payment_provider.dart';

/// The store's auto-renew flag: absent means unknown, never cancelled.
void main() {
  test('true and false, case-insensitively', () {
    expect(autoRenewFromHeader('true'), isTrue);
    expect(autoRenewFromHeader(' FALSE '), isFalse);
  });

  test('anything else is unknown', () {
    for (final value in [null, '', 'maybe', '0', '1']) {
      expect(autoRenewFromHeader(value), isNull, reason: '$value');
    }
  });

  test('a store plan renews itself unless the flag says it was cancelled', () {
    expect(renewsItself(provider: 'app_store', autoRenew: null), isTrue, reason: "unknown keeps today's behaviour");
    expect(renewsItself(provider: 'google_play', autoRenew: true), isTrue);
    expect(renewsItself(provider: 'app_store', autoRenew: false), isFalse);
    expect(renewsItself(provider: 'nowpayments', autoRenew: true), isFalse, reason: 'web billing never renews itself');
    expect(renewsItself(provider: null, autoRenew: null), isFalse);
  });
}
