import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/model/account_status.dart';

void main() {
  group('AccountStatus.fromApi', () {
    test('maps every known wire value', () {
      expect(AccountStatus.fromApi('active'), AccountStatus.active);
      expect(AccountStatus.fromApi('pending_payment'), AccountStatus.pendingPayment);
      expect(AccountStatus.fromApi('pending_activation'), AccountStatus.pendingActivation);
      expect(AccountStatus.fromApi('pending_verification'), AccountStatus.pendingVerification);
      expect(AccountStatus.fromApi('expired'), AccountStatus.expired);
      expect(AccountStatus.fromApi('suspended'), AccountStatus.suspended);
      expect(AccountStatus.fromApi('deactivated'), AccountStatus.deactivated);
    });

    test('unknown / null fall back to unknown', () {
      expect(AccountStatus.fromApi('something_else'), AccountStatus.unknown);
      expect(AccountStatus.fromApi(null), AccountStatus.unknown);
    });
  });
}
