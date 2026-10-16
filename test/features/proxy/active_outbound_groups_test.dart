import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/active/active_outbound_groups.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The fast failover's view of the core is re-opened for every core session.
/// The core's stream ends with its session, so a single subscription taken
/// before connecting (the old wiring) saw nothing at all on desktop.
void main() {
  late _FakeProxyRepository repository;
  late StateController<bool> running;
  late ProviderContainer container;
  late List<List<OutboundGroup>> seen;

  final runningProvider = StateProvider<bool>((ref) => false);

  setUp(() {
    repository = _FakeProxyRepository();
    container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWith((ref) => ref.watch(runningProvider)),
        proxyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    running = container.read(runningProvider.notifier);
    seen = [];
    container.listen(activeOutboundGroupsProvider, (_, next) {
      final value = next.valueOrNull;
      if (value != null) seen.add(value);
    }, fireImmediately: true);
  });

  tearDown(() => container.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  OutboundGroup group(String tag, int delay) => OutboundGroup(
    tag: 'select',
    items: [OutboundInfo(tag: tag, urlTestDelay: delay)],
  );

  test('no core session: an empty list, and nothing subscribed', () async {
    await settle();
    expect(seen.last, isEmpty);
    expect(repository.subscriptions, 0);
  });

  test('a session subscribes once and passes its results through', () async {
    running.state = true;
    await settle();
    expect(repository.subscriptions, 1);

    repository.emit(right([group('EXIT-Tokyo', 65535)]));
    await settle();
    expect(seen.last.single.items.single.urlTestDelay, 65535);
  });

  test('an error from the core reads as nothing to judge', () async {
    running.state = true;
    await settle();
    repository.emit(right([group('EXIT-Tokyo', 65535)]));
    repository.emit(left(const ProxyFailure.unexpected('hiddify service not found')));
    await settle();
    expect(seen.last, isEmpty);
  });

  test('a core restart re-subscribes and drops the old stream', () async {
    running.state = true;
    await settle();
    container.read(coreRestartSignalProvider.notifier).restart();
    await settle();
    expect(repository.subscriptions, 2);
    expect(repository.cancelled, 1);
  });

  test('a disconnect drops the stream and reads empty; the next connect subscribes again', () async {
    running.state = true;
    await settle();
    repository.emit(right([group('EXIT-Tokyo', 65535)]));
    await settle();

    running.state = false;
    await settle();
    expect(repository.cancelled, 1);
    expect(seen.last, isEmpty);

    running.state = true;
    await settle();
    expect(repository.subscriptions, 2);
  });
}

class _FakeProxyRepository implements ProxyRepository {
  int subscriptions = 0;
  int cancelled = 0;
  late StreamController<Either<ProxyFailure, List<OutboundGroup>>> _current;

  void emit(Either<ProxyFailure, List<OutboundGroup>> event) => _current.add(event);

  @override
  Stream<Either<ProxyFailure, List<OutboundGroup>>> watchActiveProxies() {
    final controller = StreamController<Either<ProxyFailure, List<OutboundGroup>>>(
      onListen: () => subscriptions++,
      onCancel: () => cancelled++,
    );
    _current = controller;
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
