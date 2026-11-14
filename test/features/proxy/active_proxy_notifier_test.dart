import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The active outbound behind the connect button. Its gRPC stream drops when
/// iOS suspends the app, and nothing reopened it: the button stayed on
/// Connecting over a working tunnel (upstream 8e95f602).
///
/// testWidgets for its fake clock, so the reopen timers run without real waits.
void main() {
  late _FakeProxyRepository repository;
  late ProviderContainer container;
  late StateController<bool> running;

  final runningProvider = StateProvider<bool>((ref) => true);

  Future<void> start(WidgetTester tester) async {
    repository = _FakeProxyRepository();
    container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWith((ref) => ref.watch(runningProvider)),
        proxyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    running = container.read(runningProvider.notifier);
    container.listen(activeProxyNotifierProvider, (_, _) {}, fireImmediately: true);
    await tester.pump();
  }

  List<OutboundGroup> groups(String tag, int delay) => [
    OutboundGroup(tag: 'select', items: [OutboundInfo(tag: tag, urlTestDelay: delay)]),
  ];

  OutboundInfo? current() => container.read(activeProxyNotifierProvider).valueOrNull;

  testWidgets('a failed event leaves the last outbound in place', (tester) async {
    await start(tester);
    repository.emit(right(groups('EXIT-Tokyo', 120)));
    await tester.pump();
    expect(current()?.urlTestDelay, 120);

    repository.emit(left(const ProxyFailure.unexpected('connection reset')));
    await tester.pump();

    expect(current()?.tag, 'EXIT-Tokyo', reason: 'an empty outbound reads as Connecting on the button');
    expect(current()?.urlTestDelay, 120);
  });

  testWidgets('the stream is opened again two seconds after it ends', (tester) async {
    await start(tester);
    expect(repository.subscriptions, 1);

    repository.end();
    await tester.pump(const Duration(milliseconds: 1900));
    expect(repository.subscriptions, 1);

    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.subscriptions, 2);
  });

  testWidgets('reopening that keeps failing waits longer each time', (tester) async {
    // upstream 364a935a: 2 s, then 4 s, so an unreachable core is not retried,
    // and logged, every 2 seconds.
    await start(tester);
    repository.end();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.subscriptions, 2);

    repository.end();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.subscriptions, 2, reason: 'the second wait is 4 s');
    await tester.pump(const Duration(seconds: 2));
    expect(repository.subscriptions, 3);
  });

  testWidgets('a stream that delivers again goes back to the short wait', (tester) async {
    await start(tester);
    repository.end();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.subscriptions, 2);

    // The first event is the cached replay; the second proves the stream works.
    repository
      ..emit(right(groups('EXIT-Tokyo', 120)))
      ..emit(right(groups('EXIT-Tokyo', 130)));
    await tester.pump();
    repository.end();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.subscriptions, 3);
  });

  testWidgets('a disconnect cancels a pending reopen', (tester) async {
    await start(tester);
    repository.end();
    await tester.pump();

    running.state = false;
    await tester.pump(const Duration(seconds: 5));

    expect(repository.subscriptions, 1);
  });
}

class _FakeProxyRepository implements ProxyRepository {
  int subscriptions = 0;
  late StreamController<Either<ProxyFailure, List<OutboundGroup>>> _active;

  void emit(Either<ProxyFailure, List<OutboundGroup>> event) => _active.add(event);

  /// Ends the stream the way gRPC does when its connection drops.
  void end() => _active.close();

  @override
  Stream<Either<ProxyFailure, List<OutboundGroup>>> watchActiveProxies() {
    final controller = StreamController<Either<ProxyFailure, List<OutboundGroup>>>(onListen: () => subscriptions++);
    _active = controller;
    return controller.stream;
  }

  @override
  Stream<Either<ProxyFailure, OutboundGroup?>> watchProxies() => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, oldipinfo.IpInfo> getCurrentIpInfo(CancelToken cancelToken) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> selectProxy(String groupTag, String outboundTag) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> urlTest(String groupTag) => throw UnimplementedError();
}
