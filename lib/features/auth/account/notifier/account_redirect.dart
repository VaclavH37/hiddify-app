import 'dart:async';

import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_redirect.g.dart';

/// Screens a pushed renewal would interrupt: it is already up, the user is
/// mid-purchase or mid-deletion, or the app is still pre-auth.
const _quietLocations = ['/renew', '/auth', '/disclosure', '/upgrade', '/account/delete'];

/// Whether a verdict change should open the renewal screen: only on the
/// transition INTO a blocked state (a later poll refreshing the details is not
/// a new event), and never over a screen where it would interrupt.
bool shouldRedirect({required AccountState? previous, required AccountState next, required String location}) {
  if (!next.blocksConnect) return false;
  if (previous != null && previous.blocksConnect) return false;
  return !_quietLocations.any(location.startsWith);
}

/// Pushes `/renew` when a refresh returns an account verdict, and once at
/// launch when the stored verdict already blocks. Eager-started from
/// `App.build` once a profile exists.
@Riverpod(keepAlive: true)
class AccountRedirect extends _$AccountRedirect with AppLogger {
  static const _retry = Duration(milliseconds: 250);

  /// Ten seconds for the router to swap its loading config for the real one.
  static const _maxRetries = 40;

  @override
  void build() {
    ref.listen(accountStateNotifierProvider, (previous, next) => _maybePush(previous, next));
    _maybePush(null, ref.read(accountStateNotifierProvider));
  }

  void _maybePush(AccountState? previous, AccountState next, {int attempt = 0}) {
    if (!next.blocksConnect) return;
    // The route table arrives once the breakpoint is known; before that there
    // is no `renew` to resolve.
    if (ref.read(routingConfigNotifierProvider) == loadingConfig) {
      if (attempt < _maxRetries) {
        Future<void>.delayed(_retry, () => _maybePush(previous, next, attempt: attempt + 1));
      }
      return;
    }
    final router = ref.read(goRouterNotiferProvider);
    final location = router.routerDelegate.currentConfiguration.uri.path;
    if (!shouldRedirect(previous: previous, next: next, location: location)) return;
    loggy.info("account verdict on file; opening the renewal screen");
    router.pushNamed('renew');
  }
}
