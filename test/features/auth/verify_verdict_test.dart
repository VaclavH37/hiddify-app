import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/payment/model/verify_verdict.dart';

/// A verify 200 names the account's state. The screen follows that field,
/// never the presence of a link: a 200 without a link used to read as
/// "activating" even when the backend was saying the subscription had ended.
void main() {
  test('active, with and without the link', () {
    expect(
      VerifyVerdict.parse({'status': 'ok', 'account_status': 'active', 'subscription_url': 'rayn://import/A'}),
      isA<VerifyActive>().having((v) => v.link, 'link', 'rayn://import/A'),
    );
    expect(
      VerifyVerdict.parse({'status': 'ok', 'account_status': 'active'}),
      isA<VerifyActive>().having((v) => v.link, 'link', isNull),
    );
    expect(
      VerifyVerdict.parse({'account_status': 'active', 'subscription_url': ''}),
      isA<VerifyActive>().having((v) => v.link, 'link', isNull),
    );
  });

  test("expired carries the store's reason when it gave one", () {
    for (final (raw, want) in const [
      ('billing_retry', StoreStatus.billingRetry),
      ('expired', StoreStatus.expired),
      ('revoked', StoreStatus.revoked),
      ('something-new', StoreStatus.unknown),
      (null, StoreStatus.unknown),
    ]) {
      expect(
        VerifyVerdict.parse({'account_status': 'expired', if (raw != null) 'store_status': raw}),
        isA<VerifyEnded>().having((v) => v.storeStatus, 'storeStatus', want),
        reason: 'store_status $raw',
      );
    }
  });

  test("another state maps to the middleware's code vocabulary", () {
    expect(
      VerifyVerdict.parse({'account_status': 'suspended'}),
      isA<VerifyUnavailable>().having((v) => v.code, 'code', 'ACCOUNT_SUSPENDED'),
    );
    expect(
      VerifyVerdict.parse({'account_status': 'deactivated'}),
      isA<VerifyUnavailable>().having((v) => v.code, 'code', 'ACCOUNT_DEACTIVATED'),
    );
    expect(
      VerifyVerdict.parse({'account_status': 'self_deleted'}),
      isA<VerifyUnavailable>().having((v) => v.code, 'code', 'ACCOUNT_DELETED'),
    );
    expect(
      VerifyVerdict.parse({'account_status': 'frozen'}),
      isA<VerifyUnavailable>().having((v) => v.code, 'code', 'FROZEN'),
    );
  });

  test('absent: the backend has not said, the link decides', () {
    expect(
      VerifyVerdict.parse({'status': 'ok', 'subscription_url': 'rayn://import/A'}),
      isA<VerifyUnknown>().having((v) => v.link, 'link', 'rayn://import/A'),
    );
    expect(VerifyVerdict.parse({'status': 'ok'}), isA<VerifyUnknown>().having((v) => v.link, 'link', isNull));
    expect(VerifyVerdict.parse({'account_status': 42}), isA<VerifyUnknown>());
  });

  // The backend reports a stored state other than active only when the
  // verified subscription has already ended, so none of these is "unknown":
  // the fallback fetch would 403 and the user would read "activating".
  test('a pending state means nothing was granted, never unknown', () {
    expect(
      VerifyVerdict.parse({'account_status': 'pending_payment', 'store_status': 'expired'}),
      isA<VerifyEnded>().having((v) => v.storeStatus, 'storeStatus', StoreStatus.expired),
    );
    expect(VerifyVerdict.parse({'account_status': 'pending_verification'}), isA<VerifyNotEligible>());
    expect(
      VerifyVerdict.parse({'account_status': 'pending_activation', 'subscription_url': 'rayn://import/A'}),
      isA<VerifyPending>(),
    );
  });

  test('status is matched without regard to case or padding', () {
    expect(VerifyVerdict.parse({'account_status': ' Active '}), isA<VerifyActive>());
    expect(VerifyVerdict.parse({'account_status': 'EXPIRED'}), isA<VerifyEnded>());
  });
}
