import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
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

  test('a stop with a different failure is a change; the same failure again is not', () async {
    const denied = CoreStatus.stopped(alert: CoreAlert.requestVPNPermission, message: 'denied');
    expect(await seen(const [CoreStatus.started(), denied, denied, CoreStatus.stopped()]), const [
      Connected(),
      Disconnected(ConnectionFailure.missingVpnPermission('denied')),
      Disconnected(),
    ]);
  });
}
