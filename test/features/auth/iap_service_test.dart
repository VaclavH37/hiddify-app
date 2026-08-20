import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/rayn_link_fixture.dart';

/// Session store stub — overrides only `read` (the platform channel is never hit).
class _FakeStore extends SessionTokenStore {
  _FakeStore(this._token) : super(const FlutterSecureStorage());

  final String? _token;

  @override
  Future<String?> read() async => _token;
}

/// AuthApiClient stub — `post` (verify) either throws a typed error or returns a
/// body, and records what it was asked to send so the per-store request shape
/// can be asserted.
class _FakeClient extends AuthApiClient {
  _FakeClient({this.error, this.response = const {}})
      : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final AuthApiException? error;
  final Map<String, dynamic> response;

  String? lastPath;
  Map<String, dynamic>? lastBody;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? bearer}) async {
    lastPath = path;
    lastBody = body;
    if (error != null) throw error!;
    return response;
  }
}

/// Native billing-host stub. Only [finishPurchase] is exercised — it is the one
/// call whose *timing* is a correctness invariant (never before a verify 200).
class _FakeBilling implements RaynBilling {
  final List<String> finished = [];

  // Both fields must keep Pigeon's generated names to satisfy the interface.
  @override
  // ignore: non_constant_identifier_names
  final BinaryMessenger? pigeonVar_binaryMessenger = null;

  @override
  // ignore: non_constant_identifier_names
  final String pigeonVar_messageChannelSuffix = '';

  @override
  Future<void> finishPurchase(String purchaseToken) async => finished.add(purchaseToken);

  @override
  Future<BillingConnState> connect() async => BillingConnState.connected;

  @override
  Future<List<RaynOffer>> queryOffers(String productId) async => const [];

  @override
  Future<LaunchResult> launchPurchase(String offerToken, String obfuscatedAccountId) async =>
      LaunchResult(responseCode: 0);

  @override
  Future<List<RaynPurchase>> queryActivePurchases() async => const [];

  @override
  Future<void> endConnection() async {}
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
  IapStore store = IapStore.googlePlay,
}) async {
  final all = await _outcomes(
    count: 1,
    responseCode: responseCode,
    purchases: purchases,
    verifyError: verifyError,
    verifyResponse: verifyResponse,
    token: token,
    store: store,
  );
  return all.isEmpty ? null : all.first;
}

/// What one verify attempt sent and settled: the recorded request plus every
/// purchase id the store was told to finish.
typedef _VerifyTrace = ({String? path, Map<String, dynamic>? body, List<String> finished});

/// Run a single PURCHASED update to completion and report what crossed both
/// boundaries — the HTTP request, and the finish call to the native host.
Future<_VerifyTrace> _trace({
  required IapStore store,
  AuthApiException? verifyError,
  Map<String, dynamic> verifyResponse = const {'status': 'ok', 'subscription_url': 'rayn://import/AAAA'},
}) async {
  final client = _FakeClient(error: verifyError, response: verifyResponse);
  final billing = _FakeBilling();
  final container = ProviderContainer(
    overrides: [
      sessionTokenStoreProvider.overrideWithValue(_FakeStore('tok-123')),
      authApiClientProvider.overrideWithValue(client),
      // `supported: true` is what lets a Windows/Linux test host exercise the
      // native path at all; production derives it from the platform.
      iapServiceProvider.overrideWith((ref) => IapService(ref, store: store, billing: billing, supported: true)),
    ],
  );
  addTearDown(container.dispose);

  final service = container.read(iapServiceProvider);
  final settled = service.outcomes.first;
  service.onPurchasesUpdated([_purchase()], 0);
  try {
    await settled.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    // fall through — the assertions below report what actually happened
  }
  return (path: client.lastPath, body: client.lastBody, finished: billing.finished);
}

/// As [_outcome], but collects the first [count] outcomes. A successful verify
/// emits `activating` before the import result, so the terminal outcome of the
/// verify→import chain is the second element.
Future<List<IapPurchaseOutcome>> _outcomes({
  required int count,
  required int responseCode,
  List<RaynPurchase>? purchases,
  AuthApiException? verifyError,
  Map<String, dynamic> verifyResponse = const {},
  String? token = 'tok-123',
  IapStore store = IapStore.googlePlay,
}) async {
  final container = ProviderContainer(
    overrides: [
      sessionTokenStoreProvider.overrideWithValue(_FakeStore(token)),
      authApiClientProvider.overrideWithValue(_FakeClient(error: verifyError, response: verifyResponse)),
      iapServiceProvider.overrideWith((ref) => IapService(ref, store: store)),
    ],
  );
  addTearDown(container.dispose);

  final service = container.read(iapServiceProvider);
  final collected = service.outcomes.take(count).toList(); // subscribe before triggering
  service.onPurchasesUpdated(purchases ?? [_purchase()], responseCode);
  try {
    return await collected.timeout(const Duration(seconds: 3));
  } on TimeoutException {
    return const [];
  }
}

void main() {
  // The Apple traces construct an IapService with `supported: true`, which
  // registers the RaynBillingEvents handler on the default binary messenger.
  TestWidgetsFlutterBinding.ensureInitialized();

  const billingOk = 0;
  const billingUserCanceled = 1;

  setUp(useTestSecret);
  tearDown(useEmbeddedKey);

  group('IapService.onPurchasesUpdated', () {
    test('a cryptolink this build cannot open → updateRequired (purchase is safe)', () async {
      final outcomes = await _outcomes(
        count: 2,
        responseCode: billingOk,
        verifyResponse: {
          'status': 'ok',
          'subscription_url': mintRaynLink('https://sub.example.com/s/tok', version: 0x03),
        },
      );
      expect(outcomes.first, IapPurchaseOutcome.activating);
      expect(outcomes.last, IapPurchaseOutcome.updateRequired);
    });

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

    test('403 FAMILY_SHARED → familyShared (its own end state, not generic)', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        store: IapStore.appStore,
        verifyError: const AuthApiException(status: 403, code: 'FAMILY_SHARED', message: ''),
      );
      expect(outcome, IapPurchaseOutcome.familyShared);
    });

    test('404 TRANSACTION_NOT_FOUND → failed (a config bug, not a user error)', () async {
      final outcome = await _outcome(
        responseCode: billingOk,
        store: IapStore.appStore,
        verifyError: const AuthApiException(status: 404, code: 'TRANSACTION_NOT_FOUND', message: ''),
      );
      expect(outcome, IapPurchaseOutcome.failed);
    });
  });

  group('verify request shape', () {
    test('Play posts purchaseToken to /iap/google/verify', () async {
      final t = await _trace(store: IapStore.googlePlay);
      expect(t.path, '/iap/google/verify');
      expect(t.body, {'purchaseToken': 'pt-123', 'productId': 'rayn_premium'});
    });

    test('Apple posts transactionId to /iap/apple/verify, as a string', () async {
      final t = await _trace(store: IapStore.appStore);
      expect(t.path, '/iap/apple/verify');
      expect(t.body, {'transactionId': 'pt-123', 'productId': 'rayn_premium'});
      // Apple's Transaction.id is a UInt64; sending it as a JSON number is a 400.
      expect(t.body!['transactionId'], isA<String>());
    });
  });

  // Finishing a transaction tells StoreKit to stop redelivering it. Doing that
  // before the backend has recorded the purchase destroys it: the user is
  // charged, the entitlement is never granted, and nothing ever replays. These
  // are the tests that keep that from happening.
  group('finishPurchase timing', () {
    test('called exactly once, with the transaction id, after a verify 200', () async {
      final t = await _trace(store: IapStore.appStore);
      expect(t.finished, ['pt-123']);
    });

    for (final (label, error) in const <(String, AuthApiException)>[
      ('401', AuthApiException(status: 401, message: '')),
      ('403 ACCOUNT_MISMATCH', AuthApiException(status: 403, code: 'ACCOUNT_MISMATCH', message: '')),
      ('403 FAMILY_SHARED', AuthApiException(status: 403, code: 'FAMILY_SHARED', message: '')),
      ('404 TRANSACTION_NOT_FOUND', AuthApiException(status: 404, code: 'TRANSACTION_NOT_FOUND', message: '')),
      ('409 TOKEN_IN_USE', AuthApiException(status: 409, code: 'TOKEN_IN_USE', message: '')),
      ('429', AuthApiException(status: 429, message: '')),
      ('500', AuthApiException(status: 500, message: '')),
      ('transport failure', AuthApiException(status: 0, message: 'no route')),
    ]) {
      test('never called on $label — the purchase must stay redeliverable', () async {
        final t = await _trace(store: IapStore.appStore, verifyError: error);
        expect(t.finished, isEmpty);
      });
    }
  });
}
