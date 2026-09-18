import 'dart:io';

import 'package:hiddify/features/auth/login/data/session_token_store.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'iap_launch_reverify.g.dart';

/// Replays, once at launch, the store purchases whose verify never got its
/// answer.
///
/// This is the acknowledgement safety net from IAP-CLIENT-INTEGRATION.md §5.5
/// and APPLE-IAP-CLIENT-INTEGRATION.md §5.6: an interrupted verify (app killed
/// or network dropped right after paying) leaves a purchase the backend has
/// not recorded. Re-verifying is idempotent server-side and, with the backend
/// returning the cryptolink inline on verify, imports the profile without
/// hitting the 15-min reauth gate. A reinstall or a new device is Restore
/// Purchases' job: the settled entitlements are replayed only on that tap.
///
/// It self-guards and stays silent:
///  - Mobile only (no native billing host elsewhere).
///  - Only with a stored account session — token-import-only users have nothing
///    to verify, and no session means verify would just `401`.
///  - Naturally bounded: at most the (≤1) active subscription is re-verified.
///  - Outcomes are pushed on [IapService.outcomes]; with no payment screen
///    mounted there's no listener, so nothing is surfaced to the user. (If a
///    purchase is restored, the imported profile triggers the router redirect.)
@Riverpod(keepAlive: true)
Future<void> iapLaunchReverify(Ref ref) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  final token = await ref.read(sessionTokenStoreProvider).read();
  if (token == null || token.isEmpty) return;

  final service = ref.read(iapServiceProvider);
  final conn = await service.connect();
  if (conn != BillingConnState.connected) return;

  // Never the settled purchases: the backend has those, and sending them at
  // every launch was one verify per launch per subscription against a limit
  // of five a minute, and on a fresh install re-verified an ended one.
  await service.replay(includeSettled: false);
}
