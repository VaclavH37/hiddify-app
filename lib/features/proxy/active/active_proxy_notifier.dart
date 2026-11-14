import 'dart:async';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/utils/resubscribe_backoff.dart';
import 'package:hiddify/core/utils/throttler.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/marketing_delay.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

part 'active_proxy_notifier.g.dart';

@Riverpod(keepAlive: true)
class ActiveProxyNotifier extends _$ActiveProxyNotifier with AppLogger {
  // Synchronous build, returning the stream rather than `async*` + `yield*`.
  // With no `await` before the first yield the whole build stays inside the
  // synchronous build phase, which is what stops this provider colliding with its
  // siblings on the home page. The repository is read, not watched, because a
  // watch registered from inside the returned stream would land after the build.
  @override
  Stream<OutboundInfo> build() {
    // ref.disposeDelay(const Duration(seconds: 20));
    ref.watch(coreRestartSignalProvider);
    final serviceRunning = ref.watch(serviceRunningProvider);
    if (serviceRunning != _lastServiceRunning) {
      _lastServiceRunning = serviceRunning;
      _reopenBackoff.reset();
    }
    if (!serviceRunning) {
      return Stream.error(const ServiceNotRunning());
    }
    Timer? reopen;
    var received = 0;
    ref.onDispose(() => reopen?.cancel());
    return ref
        .read(proxyRepositoryProvider)
        .watchActiveProxies()
        // A failed event used to become an empty outbound with no delay, which the
        // connect button shows as a Connecting that never clears while the tunnel
        // works. The last outbound stays, and the stream is reopened below.
        .where((event) => event.isRight())
        .map((event) => event.getOrElse((l) => List<OutboundGroup>.empty()))
        .map((event) => event.firstOrNull?.items.first ?? OutboundInfo())
        .map(pinDelayForMarketing)
        .map((info) {
          // The first event is the core service's cached list (startWith in
          // watchActiveGroups), sent even when the call fails. Only a later one
          // shows the stream really works.
          if (++received > 1) _reopenBackoff.reset();
          return info;
        })
        .doOnDone(() {
          // gRPC ends the stream when its connection drops, for example once iOS
          // suspends the app. serviceRunning stays true throughout, so nothing
          // else would ever open it again. While reopening keeps failing the wait
          // grows, so an unreachable core is not retried every 2 seconds.
          final wait = _reopenBackoff.next();
          loggy.debug("active proxy stream ended, reopening in $wait");
          reopen = Timer(wait, ref.invalidateSelf);
        });
  }

  final _reopenBackoff = ResubscribeBackoff();
  bool? _lastServiceRunning;

  final _urlTestThrottler = Throttler(const Duration(seconds: 1));

  Future<void> urlTest(String? groupTag_) async {
    final groupTag = groupTag_ ?? "";
    _urlTestThrottler(() async {
      if (state case AsyncData()) {
        await ref.read(hapticServiceProvider.notifier).lightImpact();
        await ref.read(proxyRepositoryProvider).urlTest(groupTag).getOrElse((err) {
          loggy.warning("error testing group", err);
          throw err;
        }).run();
      }
    });
  }
}
