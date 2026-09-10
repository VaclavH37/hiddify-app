import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/utils/throttler.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/marketing_delay.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
    if (!serviceRunning) {
      return Stream.error(const ServiceNotRunning());
    }
    return ref
        .read(proxyRepositoryProvider)
        .watchActiveProxies()
        .map((event) => event.getOrElse((l) => List<OutboundGroup>.empty()))
        .map((event) => event.firstOrNull?.items.first ?? OutboundInfo())
        .map(pinDelayForMarketing);
  }

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
