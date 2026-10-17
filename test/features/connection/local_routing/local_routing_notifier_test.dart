import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/connection/local_routing/data/egress_routing_probe.dart';
import 'package:hiddify/features/connection/local_routing/model/egress_routing.dart';
import 'package:hiddify/features/connection/local_routing/notifier/local_routing_notifier.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The IP routing warning listens to the connection, and the connection is
/// rebuilt by Riverpod's scheduler in the middle of flushing the providers that
/// depend on it. At every Windows connect (2026-10-17) the app logged
/// "Concurrent modification during iteration" over a `_HashMap<ProviderElementBase…>`
/// from that flush.
void main() {
  late ProviderContainer container;
  late _Connection connection;
  late _Proxies proxies;
  late _Routing routing;
  final errors = <Object>[];

  setUp(() {
    errors.clear();
    connection = _Connection();
    proxies = _Proxies();
    routing = _Routing();
    container = ProviderContainer(
      overrides: [
        connectionNotifierProvider.overrideWith(() => connection),
        accountStateNotifierProvider.overrideWith(() => _Account()),
        proxyRepositoryProvider.overrideWithValue(proxies),
        egressRoutingProbeProvider.overrideWithValue(routing),
      ],
    );
    // What the home page watches, so each has listeners and is refreshed by
    // the scheduler rather than on demand.
    container
      ..listen(connectionNotifierProvider, (_, _) {})
      ..listen(serviceRunningProvider, (_, _) {})
      ..listen(activeProxyNotifierProvider, (_, _) {})
      ..listen(localRoutingNotifierProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  /// Runs [change], then lets Riverpod's scheduler refresh what it dirtied.
  ///
  /// The refresh runs in a timer scheduled from inside [change], so what it
  /// throws lands in this zone's handler, not in the test's own frames.
  Future<void> applyAndSettle(void Function() change) {
    final done = Completer<void>();
    runZonedGuarded(() async {
      change();
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      done.complete();
    }, (error, _) => errors.add(error));
    return done.future;
  }

  /// The app's connect: the core starts, RaynCoreService bumps the restart
  /// signal, and the connection notifier, which watches it, rebuilds onto the
  /// new status.
  void connect() {
    connection.status = const ConnectionStatus.connected();
    container.read(coreRestartSignalProvider.notifier).restart();
  }

  final windowsOnly = !Platform.isWindows ? 'the IP routing warning only runs on Windows' : null;

  test('a connect does not rebuild a provider in the middle of its own flush', () async {
    await applyAndSettle(() {});
    await applyAndSettle(connect);

    expect(errors, isEmpty);
    expect(container.read(serviceRunningProvider), isTrue);
  }, skip: windowsOnly);

  test("the scheduler keeps refreshing after a connect: the next one isn't stranded", () async {
    // The throw used to leave Riverpod's scheduler with a refresh it believed
    // was still pending, so it never scheduled another. A provider marked
    // dirty after that waited for something to read it.
    await applyAndSettle(() {});
    await applyAndSettle(connect);

    var heard = <bool>[];
    container.listen(serviceRunningProvider, (_, next) => heard.add(next));
    await applyAndSettle(() {
      connection.status = const ConnectionStatus.disconnected();
      container.read(coreRestartSignalProvider.notifier).restart();
    });
    expect(heard, [false], reason: 'the disconnect must reach listeners without anyone reading it');

    heard = [];
    await applyAndSettle(connect);
    expect(heard, [true]);
    expect(errors, isEmpty);
  }, skip: windowsOnly);

  test('the warning still rises on a connect into a tunnel that IP routing kills', () async {
    routing.result = const EgressRouting(index: 4, alias: 'Wi-Fi', forwarding: true);
    proxies.delay = 65535;
    await applyAndSettle(() {});
    await applyAndSettle(connect);

    expect(errors, isEmpty);
    expect(container.read(localRoutingNotifierProvider)?.routing.alias, 'Wi-Fi');
  }, skip: windowsOnly);
}

/// Rebuilds on the restart signal and reports whatever [status] is at that
/// moment, the way ConnectionNotifier does: from an `async*` body, so its watch
/// of the signal runs after each build and re-registers behind the providers
/// that watch it synchronously, ActiveProxyNotifier among them. That order is
/// what puts ActiveProxyNotifier's refresh first.
class _Connection extends ConnectionNotifier {
  ConnectionStatus status = const ConnectionStatus.disconnected();

  @override
  Stream<ConnectionStatus> build() async* {
    ref.watch(coreRestartSignalProvider);
    yield status;
  }
}

class _Account extends AccountStateNotifier {
  @override
  AccountState build() => const AccountActive();
}

class _Routing implements EgressRoutingProbe {
  EgressRouting? result;

  @override
  EgressRouting? read() => result;
}

/// Each core session reports one location, with [delay] as its URL test (0:
/// not tested yet).
class _Proxies implements ProxyRepository {
  int delay = 0;

  @override
  Stream<Either<ProxyFailure, List<OutboundGroup>>> watchActiveProxies() => Stream.value(
    right([
      OutboundGroup(
        tag: 'select',
        items: [OutboundInfo(tag: 'EXIT-Tokyo', urlTestDelay: delay)],
      ),
    ]),
  );

  @override
  Stream<Either<ProxyFailure, OutboundGroup?>> watchProxies() => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, oldipinfo.IpInfo> getCurrentIpInfo(CancelToken cancelToken) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> selectProxy(String groupTag, String outboundTag) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> urlTest(String groupTag) => throw UnimplementedError();
}
