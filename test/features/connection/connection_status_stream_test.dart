import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/core_status.dart';

/// The core's status stream repeats itself (a replaying subject, a status
/// listener restarted on every core start, a stop reported twice). The app
/// sees each change once. Every connect and disconnect used to reach it twice
/// (2026-10-17 log).
void main() {
  Future<List<ConnectionStatus>> seen(List<CoreStatus> core) =>
      connectionStatusFrom(Stream.fromIterable(core)).toList();

  test('a connect: the replayed status and the restarted listener repeating it arrive once', () async {
    expect(
      await seen(const [
        CoreStatus.starting(),
        // ConnectionNotifier re-subscribes: the subject replays STARTED, then
        // the restarted gRPC listener reports STARTED again.
        CoreStatus.started(),
        CoreStatus.started(),
      ]),
      const [Connecting(), Connected()],
    );
  });

  test('a disconnect: the core and stop() each reporting the stop arrive once', () async {
    expect(await seen(const [CoreStatus.stopping(), CoreStatus.stopped(), CoreStatus.stopped()]), const [
      Disconnecting(),
      Disconnected(),
    ]);
  });

  test('every real change still arrives, including a status seen before', () async {
    expect(
      await seen(const [
        CoreStatus.stopped(),
        CoreStatus.starting(),
        CoreStatus.started(),
        CoreStatus.stopping(),
        CoreStatus.stopped(),
        CoreStatus.starting(),
        CoreStatus.started(),
      ]),
      const [Disconnected(), Connecting(), Connected(), Disconnecting(), Disconnected(), Connecting(), Connected()],
    );
  });

  group("the platform's second stop on Android and iOS", () {
    // Mobile.close stops the core again after the app has: it announces
    // STOPPING, then finds nothing running and reports ALREADY_STOPPED. Then
    // the listener ends with STOPPED, and stop() adds its own (2026-10-19).
    final secondStop = [
      const CoreStatus.stopping(),
      CoreStatus.fromCoreInfo(
        CoreInfoResponse(coreState: CoreStates.STOPPED, messageType: MessageType.ALREADY_STOPPED),
      ),
      const CoreStatus.stopped(),
      const CoreStatus.stopped(),
    ];

    test('is no failure and no second disconnect', () async {
      expect(
        await seen([
          const CoreStatus.started(),
          const CoreStatus.stopping(),
          const CoreStatus.stopped(),
          ...secondStop,
        ]),
        const [Connected(), Disconnecting(), Disconnected()],
      );
    });

    test('a failover goes straight from disconnected to connecting', () async {
      expect(
        await seen([
          const CoreStatus.started(),
          const CoreStatus.stopping(),
          const CoreStatus.stopped(),
          ...secondStop,
          const CoreStatus.starting(),
          const CoreStatus.started(),
        ]),
        const [Connected(), Disconnecting(), Disconnected(), Connecting(), Connected()],
      );
    });

    test('ALREADY_STOPPED carries no alert, while a real start failure still does', () {
      final already = CoreStatus.fromCoreInfo(
        CoreInfoResponse(coreState: CoreStates.STOPPED, messageType: MessageType.ALREADY_STOPPED),
      );
      expect(already.getCoreAlert(), isNull);
      final failed = CoreStatus.fromCoreInfo(
        CoreInfoResponse(coreState: CoreStates.STOPPED, messageType: MessageType.START_SERVICE, message: 'boom'),
      );
      expect(failed.getCoreAlert(), isA<UnexpectedConnectionFailure>());
    });

    test('cancelling a connect still shows disconnecting', () async {
      expect(await seen(const [CoreStatus.starting(), CoreStatus.stopping(), CoreStatus.stopped()]), const [
        Connecting(),
        Disconnecting(),
        Disconnected(),
      ]);
    });
  });

  test('a stop with a different failure is a change; the same failure again is not', () async {
    const denied = CoreStatus.stopped(alert: CoreAlert.requestVPNPermission, message: 'denied');
    expect(await seen(const [CoreStatus.started(), denied, denied, CoreStatus.stopped()]), const [
      Connected(),
      Disconnected(ConnectionFailure.missingVpnPermission('denied')),
      Disconnected(),
    ]);
  });
}
