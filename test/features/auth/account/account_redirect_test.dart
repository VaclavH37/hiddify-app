import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_redirect.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';

/// When a verdict opens the renewal screen on its own.
void main() {
  final at = DateTime.utc(2026, 9, 14);
  final expired = AccountExpired(details: AccountExpiry.none, detectedAt: at);
  final expiredLater = AccountExpired(
    details: const AccountExpiry(paymentProvider: 'app_store'),
    detectedAt: at,
  );
  final unavailable = AccountUnavailable(code: 'ACCOUNT_SUSPENDED', detectedAt: at);
  const active = AccountActive();

  test('the transition into a blocked state opens it, from home or settings', () {
    for (final location in ['/home', '/settings', '/home/proxies', '/settings/about']) {
      expect(
        shouldRedirect(previous: active, next: expired, location: location),
        isTrue,
        reason: location,
      );
      expect(
        shouldRedirect(previous: active, next: unavailable, location: location),
        isTrue,
        reason: location,
      );
    }
  });

  test('a stored verdict at launch opens it once', () {
    expect(shouldRedirect(previous: null, next: expired, location: '/home'), isTrue);
  });

  test('a later poll refreshing the details is not a new event', () {
    expect(shouldRedirect(previous: expired, next: expiredLater, location: '/home'), isFalse);
    expect(shouldRedirect(previous: expired, next: unavailable, location: '/home'), isFalse);
  });

  test('an active account never opens it', () {
    expect(shouldRedirect(previous: expired, next: active, location: '/home'), isFalse);
    expect(shouldRedirect(previous: null, next: active, location: '/home'), isFalse);
  });

  test('never over the screen itself, a purchase, a deletion or the pre-auth surfaces', () {
    for (final location in [
      '/renew',
      '/auth',
      '/auth/login',
      '/auth/payment',
      '/disclosure/vpn',
      '/upgrade',
      '/account/delete',
    ]) {
      expect(
        shouldRedirect(previous: active, next: expired, location: location),
        isFalse,
        reason: location,
      );
    }
  });
}
