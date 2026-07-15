import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disclosure flags default to false and persist true independently', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // PreferencesNotifier.create reads the resolved SharedPreferences instance,
    // so the async provider must complete before the flags are read.
    await container.read(sharedPreferencesProvider.future);

    expect(container.read(Preferences.vpnDisclosureAccepted), isFalse);
    expect(container.read(Preferences.dataDisclosureAccepted), isFalse);

    await container.read(Preferences.vpnDisclosureAccepted.notifier).update(true);
    expect(container.read(Preferences.vpnDisclosureAccepted), isTrue);
    // The two disclosures are independent — accepting the VPN one must not
    // implicitly accept the data one.
    expect(container.read(Preferences.dataDisclosureAccepted), isFalse);

    await container.read(Preferences.dataDisclosureAccepted.notifier).update(true);
    expect(container.read(Preferences.dataDisclosureAccepted), isTrue);
  });
}
