import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Session store stub — overrides only `read` (the platform channel is never hit).
class _FakeStore extends SessionTokenStore {
  _FakeStore(this._token) : super(const FlutterSecureStorage());

  final String? _token;

  @override
  Future<String?> read() async => _token;
}

/// AuthApiClient stub — `post` (verify) either throws a typed error or returns a body.
class _FakeClient extends AuthApiClient {
  _FakeClient({this.error, this.response = const {}})
      : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final AuthApiException? error;
  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? bearer}) async {
    if (error != null) throw error!;
    return response;
  }
}

RaynPurchase _purchase({RaynPurchaseState state = RaynPurchaseState.purchased}) => RaynPurchase(
      purchaseToken: 'pt-123',
      productId: 'rayn_premium',
      state: state,
      isAcknowledged: false,
    );

/// Drive one `onPurchasesUpdated` through a real [IapService] (with fakes) and
/// return the first outcome it emits.
Future<IapPurchaseOutcome?> _outcome({
  required int responseCode,
  List<RaynPurchase>? purchases,
  AuthApiException? verifyError,
  Map<String, dynamic> verifyResponse = const {},
  String? token = 'tok-123',
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionTokenStoreProvider.overrideWithValue(_FakeStore(token)),
      authApiClientProvider.overrideWithValue(_FakeClient(error: verifyError, response: verifyResponse)),
    ],
  );
  addTearDown(container.dispose);

  final service = container.read(iapServiceProvider);
  final first = service.outcomes.first; // subscribe before triggering
  service.onPurchasesUpdated(purchases ?? [_purchase()], responseCode);
  try {
    return await first.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    return null;
  }
}

void main() {
  const billingOk = 0;
  const billingUserCanceled = 1;

  group('IapService.onPurchasesUpdated', () {
    test('PURCHASED + verify 200 → activating (provisioning wait begins)', () async {
      // After a successful verify the first outcome is `activating` (the account
      // is being provisioned); the terminal imported/stillProvisioning follows
      // once the poll resolves. The fake cryptolink is intentionally unparseable
      // so the poll short-circuits without needing a real profile repository.
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyResponse: const {'status': 'ok', 'subscription_url': 'rayn://import/AAAA'},
      );
      expect(outcome, IapPurchaseOutcome.activating);
    });

    test('403 ACCOUNT_MISMATCH → accountMismatch', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyError: const AuthApiException(status: 403, code: 'ACCOUNT_MISMATCH', message: ''),
      );
      expect(outcome, IapPurchaseOutcome.accountMismatch);
    });

    test('409 TOKEN_IN_USE → tokenInUse', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyError: const AuthApiException(status: 409, code: 'TOKEN_IN_USE', message: ''),
      );
      expect(outcome, IapPurchaseOutcome.tokenInUse);
    });

    test('403 INELIGIBLE → ineligible', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyError: const AuthApiException(status: 403, code: 'INELIGIBLE', message: ''),
      );
      expect(outcome, IapPurchaseOutcome.ineligible);
    });

    test('401 → needsLogin', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyError: const AuthApiException(status: 401, message: ''),
      );
      expect(outcome, IapPurchaseOutcome.needsLogin);
    });

    test('429 → rateLimited', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyError: const AuthApiException(status: 429, message: ''),
      );
      expect(outcome, IapPurchaseOutcome.rateLimited);
    });

    test('transport failure → unreachable', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyError: AuthApiException.unreachable('no route'),
      );
      expect(outcome, IapPurchaseOutcome.unreachable);
    });

    test('500 → failed', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        verifyError: const AuthApiException(status: 500, message: ''),
      );
      expect(outcome, IapPurchaseOutcome.failed);
    });

    test('PENDING purchase → pendingPayment (no verify)', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        purchases: [_purchase(state: RaynPurchaseState.pending)],
      );
      expect(outcome, IapPurchaseOutcome.pendingPayment);
    });

    test('USER_CANCELED → canceled', () async {
      final outcome = await _outcome(responseCode: billingUserCanceled);
      expect(outcome, IapPurchaseOutcome.canceled);
    });

    test('no stored session → needsLogin (never calls verify)', () async {
      final outcome = await _outcome(responseCode: billingOk, token: null);
      expect(outcome, IapPurchaseOutcome.needsLogin);
    });
  });
}
