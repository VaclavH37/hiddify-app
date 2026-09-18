import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_repository.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/rayn_link_fixture.dart';

/// One verify per transaction. The purchase result, the store's updates
/// stream, a Restore tap and the launch re-verify can all deliver the same
/// transaction; on staging that made four verifies for one purchase and a 429.
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
  }) {
    final client = _CountingClient({'status': 'ok', 'subscription_url': link ?? renewedLink});
    final billing = _FakeBilling(active);
    final container = ProviderContainer(
      overrides: [
        sessionTokenStoreProvider.overrideWithValue(_FakeStore('tok-123')),
        authApiClientProvider.overrideWithValue(client),
        iapServiceProvider.overrideWith(
          (ref) => IapService(ref, store: IapStore.appStore, billing: billing, supported: true),
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

  group('restore', () {
    test('skips a finished entitlement on a device that already has a working profile', () async {
      final h = harness(profile: _remote(), active: [_purchase(acknowledged: true)]);
      expect(await h.service.restore(), isTrue);
      await settle();

      expect(h.client.verifies, 0);
      expect(h.outcomes, [IapPurchaseOutcome.alreadySettled]);
    });

    test('verifies an unfinished entitlement (an interrupted verify)', () async {
      final h = harness(profile: _remote(), active: [_purchase()]);
      await h.service.restore();
      await settle();

      expect(h.client.verifies, 1);
      expect(h.outcomes, [IapPurchaseOutcome.activating, IapPurchaseOutcome.imported]);
    });

    test('verifies on a device with no profile (reinstall, new device)', () async {
      final h = harness(active: [_purchase(acknowledged: true)]);
      await h.service.restore();
      await settle();

      expect(h.client.verifies, 1);
    });

    test('verifies when the account is blocked, even for a finished entitlement', () async {
      final h = harness(
        profile: _remote(),
        account: AccountExpired(details: AccountExpiry.none, detectedAt: DateTime.utc(2026, 9, 17)),
        active: [_purchase(acknowledged: true)],
      );
      await h.service.restore();
      await settle();

      expect(h.client.verifies, 1);
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

RaynPurchase _purchase({bool acknowledged = false}) => RaynPurchase(
  purchaseToken: 'pt-123',
  productId: 'rayn_premium',
  state: RaynPurchaseState.purchased,
  isAcknowledged: acknowledged,
  originalId: 'orig-123',
  purchaseDateMs: 1758000000000,
);

class _CountingClient extends AuthApiClient {
  _CountingClient(this.response) : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final Map<String, dynamic> response;
  int verifies = 0;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? bearer}) async {
    verifies++;
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
  Future<List<RaynPurchase>> queryActivePurchases(bool includeSettled) async => active;

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
