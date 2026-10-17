import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/foreground_retry.dart';

/// The foreground core can stop listening while an iOS app is suspended. Every
/// call to it gets one heal and one retry, and setup runs once however many
/// callers ask for it at the same moment.
void main() {
  const refused = GrpcError.unavailable('Error connecting: SocketException: Connection refused');

  group('callForegroundCore', () {
    test('a first-call success never heals', () async {
      var heals = 0;
      final result = await callForegroundCore(
        call: () async => 'ok',
        heal: (_) async {
          heals++;
          return null;
        },
      );
      expect(result, 'ok');
      expect(heals, 0);
    });

    test('an unreachable core is healed once and the call retried', () async {
      var calls = 0;
      var heals = 0;
      final result = await callForegroundCore(
        call: () async {
          calls++;
          if (calls == 1) throw refused;
          return 'parsed';
        },
        heal: (_) async {
          heals++;
          return null;
        },
      );
      expect(result, 'parsed');
      expect((calls: calls, heals: heals), (calls: 2, heals: 1));
    });

    test('still unreachable after the heal: fails, carrying why the heal failed', () async {
      final failure = await callForegroundCore<String>(
        call: () async => throw refused,
        heal: (_) async => 'port already in use',
      ).then<Object?>((_) => null, onError: (Object e) => e);

      expect(failure, isA<ForegroundCoreUnreachable>());
      final unreachable = failure! as ForegroundCoreUnreachable;
      expect(unreachable.healError, 'port already in use');
      expect(unreachable.lastError, same(refused));
    });

    test('a core that answered with another code is not restarted', () async {
      var heals = 0;
      const denied = GrpcError.unauthenticated('invalid credentials');
      await expectLater(
        callForegroundCore<String>(
          call: () async => throw denied,
          heal: (_) async {
            heals++;
            return null;
          },
        ),
        throwsA(same(denied)),
      );
      expect(heals, 0);
    });

    test('a client that was never built heals', () async {
      var built = false;
      final result = await callForegroundCore(
        call: () async {
          if (!built) throw StateError("Field 'fgClient' has not been initialized.");
          return 'ok';
        },
        heal: (_) async {
          built = true;
          return null;
        },
      );
      expect(result, 'ok');
    });

    test('the retry reads the client the heal put in place', () async {
      var client = _FakeClient(refusing: true);
      final result = await callForegroundCore(
        call: () => client.parse(),
        heal: (_) async {
          client = _FakeClient(refusing: false);
          return null;
        },
      );
      expect(result, 'parsed');
    });

    test('a caller can widen what heals', () async {
      var heals = 0;
      final result = await callForegroundCore(
        call: () async {
          if (heals == 0) throw const GrpcError.internal('parse crashed');
          return 'parsed';
        },
        heal: (_) async {
          heals++;
          return null;
        },
        shouldHeal: (_) => true,
      );
      expect(result, 'parsed');
      expect(heals, 1);
    });
  });

  group('SingleFlight', () {
    test('overlapping callers share one run; a later call starts another', () async {
      final flight = SingleFlight<int>();
      var runs = 0;
      final gate = Completer<void>();
      Future<int> task() async {
        runs++;
        await gate.future;
        return runs;
      }

      final first = flight.run(task);
      final second = flight.run(task);
      gate.complete();
      expect(await Future.wait([first, second]), [1, 1]);
      expect(runs, 1);

      expect(await flight.run(task), 2);
      expect(runs, 2);
    });

    test('a failed run does not stick', () async {
      final flight = SingleFlight<int>();
      await expectLater(flight.run(() async => throw StateError('setup failed')), throwsStateError);
      expect(await flight.run(() async => 7), 7);
    });
  });
}

class _FakeClient {
  _FakeClient({required this.refusing});
  final bool refusing;

  Future<String> parse() async {
    if (refusing) throw const GrpcError.unavailable('Connection refused');
    return 'parsed';
  }
}
