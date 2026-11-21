import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/local_proxy_auth.dart';

void main() {
  // The core derives the same password from the same secret
  // (hiddify-core/v2/config/local_proxy_auth_test.go pins this vector too). If
  // the two ever disagree, every tunnel-only fetch is refused with a 407.
  test('the password matches the core for the shared test vector', () {
    expect(
      deriveLocalProxyPassword('rayn-test-secret'),
      '4fe0e9e5aa4bd820c647025407c9e346c0faabb53ec2e05d2e146caca1fd8655',
    );
    expect(localProxyUser, 'rayn');
  });

  // A core set up without a secret builds the port without a password, and
  // the app must then send none.
  test('no secret, no password', () {
    expect(deriveLocalProxyPassword(null), isNull);
    expect(deriveLocalProxyPassword(''), isNull);
  });
}
