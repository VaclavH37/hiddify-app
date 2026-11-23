import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:toastification/toastification.dart';

/// The location list. Its gRPC stream fails whenever its connection drops, for
/// example when iOS suspends the app; the page then showed an error until it
/// was rebuilt, though the tunnel kept working (upstream 2c8b5c10).
///
/// testWidgets for its fake clock, so the reopen timers run without real waits.
void main() {
  late _FakeProxyRepository repository;
  late _RecordingToasts toasts;
  late ProviderContainer container;

  Future<void> start(WidgetTester tester) async {
    repository = _FakeProxyRepository();
    toasts = _RecordingToasts();
    container = ProviderContainer(
      overrides: [
        serviceRunningProvider.overrideWith((ref) => true),
        proxyRepositoryProvider.overrideWithValue(repository),
        proxiesSortNotifierProvider.overrideWith(_UnsortedNotifier.new),
        hapticServiceProvider.overrideWith(_NoHaptics.new),
        translationsProvider.overrideWith((ref) => AppLocale.en.buildSync()),
        inAppNotificationControllerProvider.overrideWithValue(toasts),
      ],
    );
    addTearDown(container.dispose);
    container.listen(proxiesOverviewNotifierProvider, (_, _) {}, fireImmediately: true);
    container.listen(translationsProvider, (_, _) {}, fireImmediately: true);
    await tester.pump();
  }

  OutboundGroup locations(String tag) => OutboundGroup(tag: 'select', items: [OutboundInfo(tag: tag)]);

  AsyncValue<OutboundGroup?> state() => container.read(proxiesOverviewNotifierProvider);

  testWidgets('a failed event keeps the last list on screen', (tester) async {
    await start(tester);
    repository.emit(right(locations('EXIT-Tokyo')));
    await tester.pump();

    repository.emit(left(const ProxyFailure.unexpected('connection reset')));
    await tester.pump();

    expect(state().hasError, isFalse, reason: 'an error state shows an error page over a working tunnel');
    expect(state().valueOrNull?.items.single.tag, 'EXIT-Tokyo');
  });

  testWidgets('the stream is reopened after it ends, waiting longer while it keeps failing', (tester) async {
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

  group('switching location', () {
    OutboundGroup twoLocations() => OutboundGroup(
      tag: 'select',
      selected: 'EXIT-Tokyo',
      items: [
        OutboundInfo(tag: 'EXIT-Tokyo', isSelected: true),
        OutboundInfo(tag: 'EXIT-Seoul'),
      ],
    );

    Future<void> switchToSeoul(WidgetTester tester) async {
      repository.emit(right(twoLocations()));
      await tester.pump();
      await container.read(proxiesOverviewNotifierProvider.notifier).changeProxy('select', 'EXIT-Seoul');
      await tester.pump();
    }

    // It used to throw from the tap handler, where nothing caught it: an
    // uncaught error in the log and a tap that looked ignored.
    testWidgets('a failed switch says so and keeps the location', (tester) async {
      await start(tester);
      repository.selectResult = left(const ProxyFailure.unexpected('core restarting'));
      await switchToSeoul(tester);

      expect(toasts.errors, ["Couldn't switch to this location. Try again."]);
      expect(state().valueOrNull?.selected, 'EXIT-Tokyo');
    });

    testWidgets('a switch selects the location without a toast', (tester) async {
      await start(tester);
      await switchToSeoul(tester);

      expect(repository.selected, ['select/EXIT-Seoul']);
      expect(toasts.errors, isEmpty);
      expect(state().valueOrNull?.selected, 'EXIT-Seoul');
    });
  });

  testWidgets('a list arriving again brings the wait back to 2 s', (tester) async {
    await start(tester);
    repository.end();
    await tester.pump(const Duration(seconds: 2));
    repository.emit(right(locations('EXIT-Tokyo')));
    await tester.pump();

    repository.end();
    await tester.pump(const Duration(seconds: 2));
    expect(repository.subscriptions, 3);
  });
}

class _UnsortedNotifier extends ProxiesSortNotifier {
  @override
  ProxiesSort build() => ProxiesSort.unsorted;
}

class _NoHaptics extends HapticService {
  @override
  bool build() => false;
}

class _RecordingToasts extends InAppNotificationController {
  final errors = <String>[];

  @override
  ToastificationItem? showErrorToast(String message) {
    errors.add(message);
    return null;
  }
}

class _FakeProxyRepository implements ProxyRepository {
  int subscriptions = 0;
  Either<ProxyFailure, Unit> selectResult = right(unit);
  final selected = <String>[];
  late StreamController<Either<ProxyFailure, OutboundGroup?>> _current;

  void emit(Either<ProxyFailure, OutboundGroup?> event) => _current.add(event);

  /// Ends the stream the way gRPC does when its connection drops.
  void end() => _current.close();

  @override
  Stream<Either<ProxyFailure, OutboundGroup?>> watchProxies() {
    final controller = StreamController<Either<ProxyFailure, OutboundGroup?>>(onListen: () => subscriptions++);
    _current = controller;
    return controller.stream;
  }

  @override
  Stream<Either<ProxyFailure, List<OutboundGroup>>> watchActiveProxies() => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, oldipinfo.IpInfo> getCurrentIpInfo(CancelToken cancelToken) => throw UnimplementedError();

  @override
  TaskEither<ProxyFailure, Unit> selectProxy(String groupTag, String outboundTag) => TaskEither(() async {
    if (selectResult.isRight()) selected.add('$groupTag/$outboundTag');
    return selectResult;
  });

  @override
  TaskEither<ProxyFailure, Unit> urlTest(String groupTag) => throw UnimplementedError();
}
