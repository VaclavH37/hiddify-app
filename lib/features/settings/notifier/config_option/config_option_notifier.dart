import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'config_option_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConfigOptionNotifier extends _$ConfigOptionNotifier with AppLogger {
  @override
  Future<bool> build() async {
    final serviceRunning = await ref.watch(serviceRunningProvider.future);
    final serviceSingboxOptions = ref.read(connectionRepositoryProvider).configOptionsSnapshot;

    ref.listen(ConfigOptions.singboxConfigOptions, (previous, next) async {
      if (!serviceRunning || previous == null) return;
      if (next != previous && next != serviceSingboxOptions) {
        if (_lastUpdate == null || DateTime.now().difference(_lastUpdate!) > const Duration(milliseconds: 100)) {
          _lastUpdate = DateTime.now();
          if (serviceSingboxOptions?.enableTun != next.enableTun) {
            loggy.debug("tun option changed, reconnecting");
            await ref.read(connectionNotifierProvider.notifier).toggleConnection();
            await ref.read(connectionNotifierProvider.notifier).toggleConnection();
          } else {
            final activeProfile = await ref.read(activeProfileProvider.future);
            return await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
          }
          state = AsyncData(false);
        }
      }
    }, fireImmediately: true);
    return false;
  }

  DateTime? _lastUpdate;
}
