import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/account/data/account_state_store.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The verdict blob must survive a relaunch, never leak across profiles, and
/// never lock a user out because of something unreadable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late AccountStateStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = AccountStateStore(prefs);
  });

  final detectedAt = DateTime.utc(2026, 9, 14, 10, 28, 53);
  final expired = AccountExpired(
    details: AccountExpiry(
      paymentProvider: 'app_store',
      billingPeriod: 'monthly',
      expiresAt: DateTime.utc(2026, 10, 14, 9),
      manageUrl: Uri.parse('https://apps.apple.com/account/subscriptions'),
    ),
    detectedAt: detectedAt,
  );

  test('nothing stored reads as active', () {
    expect(store.read(profileId: 'p1'), const AccountActive());
  });

  test('expired round-trips with its details', () async {
    await store.write(profileId: 'p1', state: expired);
    expect(store.read(profileId: 'p1'), expired);
  });

  test('a legacy expiry with no details round-trips as none', () async {
    final legacy = AccountExpired(details: AccountExpiry.none, detectedAt: detectedAt);
    await store.write(profileId: 'p1', state: legacy);
    expect(store.read(profileId: 'p1'), legacy);
  });

  test('unavailable round-trips', () async {
    final unavailable = AccountUnavailable(code: 'ACCOUNT_SUSPENDED', detectedAt: detectedAt);
    await store.write(profileId: 'p1', state: unavailable);
    expect(store.read(profileId: 'p1'), unavailable);
  });

  test("another profile's verdict reads as active", () async {
    await store.write(profileId: 'p1', state: expired);
    expect(store.read(profileId: 'p2'), const AccountActive());
  });

  test('writing active clears the key', () async {
    await store.write(profileId: 'p1', state: expired);
    await store.write(profileId: 'p1', state: const AccountActive());
    expect(prefs.getString(AccountStateStore.key), isNull);
    expect(store.read(profileId: 'p1'), const AccountActive());
  });

  test('clear removes the key', () async {
    await store.write(profileId: 'p1', state: expired);
    await store.clear();
    expect(prefs.getString(AccountStateStore.key), isNull);
  });

  test('a corrupt blob reads as active', () async {
    await prefs.setString(AccountStateStore.key, '{not json');
    expect(store.read(profileId: 'p1'), const AccountActive());
    await prefs.setString(AccountStateStore.key, '[1,2,3]');
    expect(store.read(profileId: 'p1'), const AccountActive());
  });

  test('an unknown kind or a missing detection time reads as active', () async {
    await prefs.setString(
      AccountStateStore.key,
      '{"profileId":"p1","kind":"frozen","detectedAt":"2026-09-14T10:28:53Z"}',
    );
    expect(store.read(profileId: 'p1'), const AccountActive());
    await prefs.setString(AccountStateStore.key, '{"profileId":"p1","kind":"expired"}');
    expect(store.read(profileId: 'p1'), const AccountActive());
  });
}
