import 'dart:async';

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
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../support/rayn_link_fixture.dart';

/// Where a verified purchase's cryptolink lands. With a profile on the device
/// (a renewal, a plan transition, the launch re-verify) it must rotate THAT
/// row in place; only the sign-up paywall, with no profile, adds one. Either
/// way a persisted config clears the account verdict.
void main() {
  setUp(useTestSecret);
  tearDown(useEmbeddedKey);

  const renewedUrl = 'https://sub.example.com/s/renewed-state';
  final renewedLink = mintRaynLink(renewedUrl);

  Future<({List<IapPurchaseOutcome> outcomes, _FakeRepo repo, _RecordingAccountState account})> run({
    ProfileEntity? profile,
  }) async {
    final repo = _FakeRepo();
    final account = _RecordingAccountState();
    final container = ProviderContainer(
      overrides: [
        sessionTokenStoreProvider.overrideWithValue(_FakeStore('tok-123')),
        authApiClientProvider.overrideWithValue(_FakeClient({'status': 'ok', 'subscription_url': renewedLink})),
        iapServiceProvider.overrideWith((ref) => IapService(ref, store: IapStore.googlePlay)),
        profileRepositoryProvider.overrideWith((ref) => repo),
        activeProfileProvider.overrideWith(() => _FixedActiveProfile(profile)),
        accountStateNotifierProvider.overrideWith(() => account),
      ],
    );
    addTearDown(container.dispose);

    final service = container.read(iapServiceProvider);
    final collected = service.outcomes.take(2).toList();
    service.onPurchasesUpdated([_purchase()], 0);
    final outcomes = await collected.timeout(const Duration(seconds: 3));
    return (outcomes: outcomes, repo: repo, account: account);
  }

  test('with a profile on the device the renewed link rotates that row in place', () async {
    final r = await run(profile: _remote('p1'));

    expect(r.outcomes, [IapPurchaseOutcome.activating, IapPurchaseOutcome.imported]);
    expect(r.repo.calls.map((c) => c.memberName), [#renewRemote]);
    final call = r.repo.calls.single;
    expect(call.namedArguments[#id], 'p1');
    expect(call.namedArguments[#url], renewedUrl);
    expect(call.namedArguments[#sourceToken], renewedLink);
    expect(r.account.cleared, 1);
  });

  test('with no profile (the sign-up paywall) the link is imported as a new profile', () async {
    final r = await run();

    expect(r.outcomes, [IapPurchaseOutcome.activating, IapPurchaseOutcome.imported]);
    expect(r.repo.calls.map((c) => c.memberName), [#upsertRemote]);
    final call = r.repo.calls.single;
    expect(call.positionalArguments, [renewedUrl]);
    expect(call.namedArguments[#sourceToken], renewedLink);
    expect(r.account.cleared, 1);
  });
}

RemoteProfileEntity _remote(String id) => RemoteProfileEntity(
  id: id,
  active: true,
  name: 'Alex',
  url: 'https://sub.example.com/s/old-state',
  lastUpdate: DateTime(2026, 9),
);

RaynPurchase _purchase() => RaynPurchase(
  purchaseToken: 'pt-123',
  productId: 'rayn_premium',
  state: RaynPurchaseState.purchased,
  isAcknowledged: false,
  originalId: 'orig-123',
  purchaseDateMs: 1758000000000,
);

/// Records the two persistence calls the import poll can make and answers
/// both with success. Everything else on the interface is unreachable here.
class _FakeRepo implements ProfileRepository {
  final calls = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #upsertRemote || invocation.memberName == #renewRemote) {
      calls.add(invocation);
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

class _RecordingAccountState extends AccountStateNotifier {
  int cleared = 0;

  @override
  AccountState build() => const AccountActive();

  @override
  Future<void> recordActive() async {
    cleared++;
    state = const AccountActive();
  }
}

class _FakeStore extends SessionTokenStore {
  _FakeStore(this._token) : super(const FlutterSecureStorage());

  final String? _token;

  @override
  Future<String?> read() async => _token;
}

class _FakeClient extends AuthApiClient {
  _FakeClient(this.response) : super(baseUrl: 'https://test.invalid', userAgent: 'test');

  final Map<String, dynamic> response;

  @override
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? bearer}) async => response;
}
