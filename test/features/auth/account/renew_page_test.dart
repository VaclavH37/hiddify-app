import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/auth/account/widget/renew_page.dart';
import 'package:hiddify/features/auth/payment/widget/plan_card.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The renewal screen per verdict. The test host is a desktop platform, so
/// the expired mode is the website variant: no store rows, no plan cards.
void main() {
  final at = DateTime.utc(2026, 9, 14);

  Widget host(AccountState state) {
    return ProviderScope(
      overrides: [
        translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
        accountStateNotifierProvider.overrideWith(() => _FixedAccountState(state)),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: Brightness.light, extensions: const [RaynPalette.light]),
        // The page reads the translations synchronously, as the app does after
        // bootstrap; the gate waits for the override to resolve.
        home: Consumer(
          builder: (context, ref, _) =>
              ref.watch(translationsProvider).hasValue ? const RenewPage() : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Future<void> pumpPage(WidgetTester tester, AccountState state) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(state));
    await tester.pump();
  }

  testWidgets('expired: what ended, the website, check again, log out — and no store rows', (tester) async {
    await pumpPage(
      tester,
      AccountExpired(
        details: AccountExpiry(
          paymentProvider: 'nowpayments',
          billingPeriod: 'monthly',
          expiresAt: DateTime.utc(2026, 9, 12, 9),
        ),
        detectedAt: at,
      ),
    );

    expect(find.text('Subscription expired'), findsOneWidget);
    expect(find.textContaining('monthly plan ended on'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Renew on the website'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Check again'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Log out'), findsOneWidget);
    expect(find.byType(PlanCard), findsNothing);
    expect(find.text('Manage subscription'), findsNothing);
  });

  testWidgets('a future end date (store refund) is not shown as a date', (tester) async {
    await pumpPage(
      tester,
      AccountExpired(
        details: AccountExpiry(
          paymentProvider: 'app_store',
          expiresAt: DateTime.now().add(const Duration(days: 20)),
          manageUrl: Uri.parse('https://apps.apple.com/account/subscriptions'),
        ),
        detectedAt: at,
      ),
    );

    expect(find.text('Your subscription has ended.'), findsOneWidget);
    expect(find.textContaining('ended on'), findsNothing);
  });

  testWidgets('a refund says so, with the day access ended, never the future expiry', (tester) async {
    await pumpPage(
      tester,
      AccountExpired(
        details: AccountExpiry(
          paymentProvider: 'app_store',
          storeStatus: AccountExpiry.storeRevoked,
          endedAt: DateTime.utc(2026, 9, 10, 12),
          expiresAt: DateTime.now().add(const Duration(days: 20)),
        ),
        detectedAt: at,
      ),
    );
    expect(find.textContaining('refunded'), findsOneWidget);
    expect(find.textContaining('ended on'), findsOneWidget);
  });

  testWidgets('a failed store payment asks for the payment method', (tester) async {
    await pumpPage(
      tester,
      AccountExpired(
        details: const AccountExpiry(paymentProvider: 'google_play', storeStatus: AccountExpiry.storeBillingRetry),
        detectedAt: at,
      ),
    );
    expect(find.textContaining("didn't go through"), findsOneWidget);
  });

  testWidgets('an early end without a store reason reads as such', (tester) async {
    await pumpPage(
      tester,
      AccountExpired(
        details: AccountExpiry(paymentProvider: 'nowpayments', endedAt: DateTime.utc(2026, 9, 10)),
        detectedAt: at,
      ),
    );
    expect(find.textContaining('ended early on'), findsOneWidget);
  });

  testWidgets('unavailable: the reason, support and log out — never a renew action', (tester) async {
    await pumpPage(tester, AccountUnavailable(code: 'ACCOUNT_SUSPENDED', detectedAt: at));

    expect(find.text('Account unavailable'), findsOneWidget);
    expect(find.textContaining('suspended'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Contact support'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Log out'), findsOneWidget);
    expect(find.text('Renew on the website'), findsNothing);
    expect(find.text('Check again'), findsNothing);
    expect(find.byType(PlanCard), findsNothing);
  });

  testWidgets('an unknown code reads as unavailable', (tester) async {
    await pumpPage(tester, AccountUnavailable(code: 'ACCOUNT_FROZEN', detectedAt: at));
    expect(find.textContaining("can't be renewed"), findsOneWidget);
    expect(find.text('Check again'), findsNothing);
  });

  testWidgets('active: nothing to do', (tester) async {
    await pumpPage(tester, const AccountActive());
    expect(find.text('Your subscription is active.'), findsOneWidget);
    expect(find.text('Check again'), findsNothing);
  });
}

class _FixedAccountState extends AccountStateNotifier {
  _FixedAccountState(this.initial);

  final AccountState initial;

  @override
  AccountState build() => initial;
}
