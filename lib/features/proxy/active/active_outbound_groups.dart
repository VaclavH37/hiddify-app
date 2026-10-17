import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_outbound_groups.g.dart';

/// The core's main selector with every location in it, each with its URL-test
/// result, for the core session that is running now.
///
/// The full outbounds stream, the one the location page reads, not the main
/// one: that carries only each group's chosen entry, so the fast failover saw
/// one location and took its failure for the hub's (2026-10-18). The selector
/// is the first group and lists every location (builder.go), and its chosen
/// entry is what traffic uses.
///
/// The core's stream belongs to one session: with no session it fails after
/// about five seconds ("hiddify service not found"), and it ends when the
/// session stops or restarts. So it is re-opened on every start, the way
/// `ActiveProxyNotifier` and `liveProxyGroupProvider` re-open theirs:
/// [serviceRunningProvider] flips on every connect, disconnect and restart, and
/// [coreRestartSignalProvider] is bumped on every start and on app resume.
///
/// The fast failover in `ForegroundProfilesUpdateNotifier` used to subscribe
/// once at app start instead. On desktop, which always starts disconnected,
/// that subscription died five seconds after launch, so the fast path never
/// ran there; on mobile it died at the first reconnect.
///
/// An empty list when no session is running, which the fast path reads as
/// "nothing to judge". A stream error reads the same way.
@Riverpod(keepAlive: true)
Stream<List<OutboundGroup>> activeOutboundGroups(Ref ref) {
  // Synchronous, returning the stream, so every dependency is registered inside
  // the build phase (see ActiveProxyNotifier.build).
  ref.watch(coreRestartSignalProvider);
  if (!ref.watch(serviceRunningProvider)) return Stream.value(const <OutboundGroup>[]);
  return ref
      .read(proxyRepositoryProvider)
      .watchProxies()
      .map((event) => event.fold((_) => const <OutboundGroup>[], (group) => group == null ? const [] : [group]));
}
