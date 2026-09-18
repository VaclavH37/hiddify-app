import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/rayn_link_fixture.dart';

/// One verify per subscription. The purchase result, the store's updates
/// stream, a Restore tap and the launch replay can all deliver the same
/// purchase, and every renewal is a new transaction of the same subscription;
/// on staging that made four verifies for one purchase, twelve more across
/// renewals, and a 429.
void main() {
  // `supported: true` registers the Pigeon handler on the binary messenger.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(useTestSecret);
  tearDown(useEmbeddedKey);

  final renewedLink = mintRaynLink('https://sub.example.com/s/renewed-state');

  ({IapService service, _CountingClient client, List<IapPurchaseOutcome> outcomes, _FakeBilling billing}) harness({
    ProfileEntity? profile,
    AccountState account = const AccountActive(),
    List<RaynPurchase> active = const [],
    String? link,
    List<AuthApiException?> script = const [],
    List<Duration> backoff = const [],
  }) {
    final client = _CountingClient({'status': 'ok', 'subscription_url': link ?? renewedLink}, script: script);
    final billing = _FakeBilling(active);
    final container = ProviderContainer(
      overrides: [
        sessionTokenStoreProvider.overrideWithValue(_FakeStore('tok-123')),
        authApiClientProvider.overrideWithValue(client),
        iapServiceProvider.overrideWith(
          (ref) => IapService(ref, store: IapStore.appStore, billing: billing, supported: true, backoff: backoff),
        ),
        profileRepositoryProvider.overrideWith((ref) => _FakeRepo()),
        activeProfileProvider.overrideWith(() => _FixedActiveProfile(profile)),
        accountStateNotifierProvider.overrideWith(() => _FixedAccountState(account)),
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(iapServiceProvider);
    final outcomes = <IapPurchaseOutcome>[];
    final sub = service.outcomes.listen(outcomes.add);
    addTearDown(sub.cancel);
    return (service: service, client: client, outcomes: outcomes, billing: billing);
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('the same transaction delivered twice is verified once; the second is already settled', () async {
    final h = harness(profile: _remote());
    h.service.onPurchasesUpdated([_purchase()], 0);
    await settle();
    h.service.onPurchasesUpdated([_purchase()], 0);
    await settle();

    expect(h.client.verifies, 1);
    expect(h.outcomes, [IapPurchaseOutcome.activating, IapPurchaseOutcome.imported, IapPurchaseOutcome.alreadySettled]);
    expect(h.billing.finished, [
      'orig-123',
      'orig-123',
    ], reason: 'finishing is idempotent and repeated on a redelivery');
  });

  test('two deliveries in the same instant produce one verify and one outcome', () async {
    final h = harness(profile: _remote());
    h.service.onPurchasesUpdated([_purchase()], 0);
    h.service.onPurchasesUpdated([_purchase()], 0);
    await settle();

    expect(h.client.verifies, 1);
    expect(h.outcomes, [IapPurchaseOutcome.activating, IapPurchaseOutcome.imported]);
  });

  test('a redelivery after a failed import retries the import, not the verify', () async {
    // An unreadable link: the import fails at parse, so the link stays pending.
    final h = harness(profile: _remote(), link: 'rayn://import/not-a-real-token');
    h.service.onPurchasesUpdated([_purchase()], 0);
    await settle();
    h.service.onPurchasesUpdated([_purchase()], 0);
    await settle();

    expect(h.client.verifies, 1);
    expect(h.outcomes, [
      IapPurchaseOutcome.activating,
      IapPurchaseOutcome.failed,
      IapPurchaseOutcome.activating,
      IapPurchaseOutcome.failed,
    ]);
  });

  test('two transactions of one subscription delivered together produce one verify', () async {
    final h = harness(profile: _remote());
    h.service.onPurchasesUpdated([_purchase(id: 'pt-old', date: 1), _purchase(id: 'pt-new', date: 2)], 0);
    await settle();

    expect(h.client.verifies, 1);
    expect(h.billing.finished, ['orig-123']);
  });

  test('a new transaction of a subscription verified earlier (a renewal) is verified once more', () async {
    final h = harness(profile: _remote());
    h.service.onPurchasesUpdated([_purchase(id: 'pt-1')], 0);
    await settle();
    h.service.onPurchasesUpdated([_purchase(id: 'pt-2', date: 1758000000001)], 0);
    await settle();

    expect(h.client.verifies, 2, reason: 'a renewal backs up the store notification to the backend');
  });

  group('replay', () {
    test('the launch replay asks for unfinished purchases only and verifies them', () async {
      final h = harness(profile: _remote(), active: [_purchase()]);
      expect(await h.service.replay(includeSettled: false), isTrue);
      await settle();

      expect(h.billing.queries, [false]);
      expect(h.client.verifies, 1);
      expect(h.outcomes, [IapPurchaseOutcome.activating, IapPurchaseOutcome.imported]);
    });

    test('the launch replay finds nothing when the store holds only settled purchases', () async {
      final h = harness(active: [_purchase(acknowledged: true)]);
      expect(await h.service.replay(includeSettled: false), isFalse);
      await settle();

      expect(h.client.verifies, 0, reason: 'the backend has every settled purchase already');
      expect(h.outcomes, isEmpty);
    });

    test('Restore asks for the settled ones too, one verify per subscription, the newest transaction', () async {
      final h = harness(
        profile: _remote(),
        active: [
          _purchase(id: 'pt-a-old', subscription: 'sub-a', date: 1, acknowledged: true),
          _purchase(id: 'pt-a-new', subscription: 'sub-a', date: 2, acknowledged: true),
          _purchase(id: 'pt-b', subscription: 'sub-b', date: 1),
        ],
      );
      expect(await h.service.restore(), isTrue);
      await settle();

      expect(h.billing.queries, [true]);
      expect(h.client.verifies, 2);
      expect(h.client.sent, ['pt-a-new', 'pt-b']);
      expect(h.billing.finished, ['sub-a', 'sub-b']);
    });

    test('Restore verifies a settled entitlement even on a device with a working profile', () async {
      final h = harness(profile: _remote(), active: [_purchase(acknowledged: true)]);
      await h.service.restore();
      await settle();

      expect(h.client.verifies, 1);
    });
  });

  group('refusals', () {
    test('a terminal refusal finishes the subscription and is answered from memory afterwards', () async {
      final h = harness(
        profile: _remote(),
        script: [const AuthApiException(status: 404, code: 'TRANSACTION_NOT_FOUND', message: '')],
      );
      h.service.onPurchasesUpdated([_purchase()], 0);
      await settle();
      h.service.onPurchasesUpdated([_purchase(id: 'pt-sibling')], 0);
      await settle();

      expect(h.client.verifies, 1);
      expect(h.billing.finished, ['orig-123']);
      expect(h.outcomes, [IapPurchaseOutcome.failed, IapPurchaseOutcome.failed]);
    });

    test('a 429 walks the ladder, then leaves the transaction unfinished', () async {
      final h = harness(
        profile: _remote(),
        script: List.filled(3, const AuthApiException(status: 429, message: '')),
        backoff: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
      );
      h.service.onPurchasesUpdated([_purchase()], 0);
      await settle();

      expect(h.client.verifies, 3, reason: 'one attempt per rung after the first');
      expect(h.billing.finished, isEmpty);
      expect(h.outcomes, [IapPurchaseOutcome.rateLimited]);
    });

    test('a 5xx that clears on a later rung ends in one finished, imported purchase', () async {
      final h = harness(
        profile: _remote(),
        script: [
          const AuthApiException(status: 503, message: ''),
          const AuthApiException(status: 500, message: ''),
        ],
        backoff: const [Duration(milliseconds: 1), Duration(milliseconds: 1)],
      );
      h.service.onPurchasesUpdated([_purchase()], 0);
      await settle();

      expect(h.client.verifies, 3);
      expect(h.billing.finished, ['orig-123']);
      expect(h.outcomes, [IapPurchaseOutcome.activating, IapPurchaseOutcome.imported]);
    });

    test('a 401 is neither retried nor finished', () async {
      final h = harness(
        profile: _remote(),
        script: [const AuthApiException(status: 401, message: '')],
        backoff: const [Duration(milliseconds: 1)],
      );
      h.service.onPurchasesUpdated([_purchase()], 0);
      await settle();

      expect(h.client.verifies, 1);
      expect(h.billing.finished, isEmpty);
      expect(h.outcomes, [IapPurchaseOutcome.needsLogin]);
    });
  });

  group('newestPerSubscription', () {
    test('keeps the newest transaction of each subscription, in first-seen order', () {
      final picked = newestPerSubscription([
        _purchase(id: 'b1', subscription: 'b', date: 5),
        _purchase(id: 'a1', subscription: 'a', date: 1),
        _purchase(id: 'a2', subscription: 'a', date: 3),
        _purchase(id: 'b0', subscription: 'b', date: 4),
      ]);
      expect(picked.map((p) => p.purchaseToken), ['b1', 'a2']);
    });

    test('a purchase without a subscription id stands alone', () {
      final picked = newestPerSubscription([
        _purchase(id: 'x', subscription: ''),
        _purchase(id: 'y', subscription: ''),
      ]);
      expect(picked.map((p) => p.purchaseToken), ['x', 'y']);
    });
  });
}

RemoteProfileEntity _remote() => RemoteProfileEntity(
  id: 'p1',
  active: true,
  name: 'Alex',
  url: 'https://sub.example.com/s/old-state',
  lastUpdate: DateTime(2026, 9),
);

RaynPurchase _purchase({
  bool acknowledged = false,
  String id = 'pt-123',
  String subscription = 'orig-123',
  int date = 1758000000000,
}) => RaynPurchase(
  purchaseToken: id,
  productId: 'rayn_premium',
  state: RaynPurchaseState.purchased,
  isAcknowledged: acknowledged,
  originalId: subscription,
  purchaseDateMs: date,
);

/// Counts verifies, records the transaction id each one sent, and answers the
/// first calls from [script] (an error to throw, or null for the success body)
/// before falling back to [response].
class _CountingClient extends AuthApiClient {
  _CountingClient(this.response, {this.script = const []}) : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final Map<String, dynamic> response;
  final List<AuthApiException?> script;
  final List<String> sent = [];
  int verifies = 0;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? bearer}) async {
    final call = verifies++;
    sent.add(body['transactionId'] as String);
    if (call < script.length) {
      final error = script[call];
      if (error != null) throw error;
    }
    return response;
  }
}

class _FakeStore extends SessionTokenStore {
  _FakeStore(this._token) : super(const FlutterSecureStorage());

  final String? _token;

  @override
  Future<String?> read() async => _token;
}

class _FakeBilling implements RaynBilling {
  _FakeBilling(this.active);

  final List<RaynPurchase> active;
  final List<String> finished = [];
  final List<bool> queries = [];

  @override
  // ignore: non_constant_identifier_names
  final BinaryMessenger? pigeonVar_binaryMessenger = null;

  @override
  // ignore: non_constant_identifier_names
  final String pigeonVar_messageChannelSuffix = '';

  @override
  Future<void> finishSubscription(String originalId) async => finished.add(originalId);

  @override
  Future<BillingConnState> connect() async => BillingConnState.connected;

  @override
  Future<List<RaynOffer>> queryOffers(String productId) async => const [];

  @override
  Future<LaunchResult> launchPurchase(String offerToken, String obfuscatedAccountId) async =>
      LaunchResult(responseCode: 0);

  @override
  // Mirrors the native contract: without includeSettled only the purchases
  // the backend has not settled.
  Future<List<RaynPurchase>> queryActivePurchases(bool includeSettled) async {
    queries.add(includeSettled);
    return includeSettled ? active : active.where((p) => !p.isAcknowledged).toList();
  }

  @override
  Future<void> endConnection() async {}
}

class _FakeRepo implements ProfileRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #upsertRemote || invocation.memberName == #renewRemote) {
      return TaskEither<ProfileFailure, Unit>.right(unit);
    }
    return super.noSuchMethod(invocation);
  }
}

class _FixedActiveProfile extends ActiveProfile {
  _FixedActiveProfile(this.profile);

  final ProfileEntity? profile;

  @override
  Stream<ProfileEntity?> build() => Stream.value(profile);
}

class _FixedAccountState extends AccountStateNotifier {
  _FixedAccountState(this.initial);

  final AccountState initial;

  @override
  AccountState build() => initial;

  @override
  Future<void> recordActive() async {}
}
