import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/background_time.dart';

/// On iOS a core start the app drives must finish even if the user leaves the
/// app part-way: the tunnel is up by then and waits for the app's `Start`.
/// [BackgroundTime] holds the platform's grace period around that work.
void main() {
  late List<String> calls;
  late BackgroundTime time;

  setUp(() {
    calls = [];
    time = BackgroundTime(begin: () async => calls.add('begin'), end: () async => calls.add('end'));
  });

  test('a hold asks once, around the work, and returns its result', () async {
    final result = await time.hold(() async {
      calls.add('body');
      return 42;
    });
    expect(result, 42);
    expect(calls, ['begin', 'body', 'end']);
  });

  test('nested holds ask the platform only once', () async {
    // A failover holds time around its stop, start and probe, and the start
    // holds time of its own.
    await time.hold(() async {
      await time.hold(() async => calls.add('start'));
      calls.add('probe');
    });
    expect(calls, ['begin', 'start', 'probe', 'end']);
  });

  test('overlapping holds release only when the last one finishes', () async {
    final first = time.hold(() => Future<void>.delayed(const Duration(milliseconds: 20), () => calls.add('first')));
    final second = time.hold(() => Future<void>.delayed(const Duration(milliseconds: 5), () => calls.add('second')));
    await Future.wait([first, second]);
    expect(calls, ['begin', 'second', 'first', 'end']);
  });

  test('a body that throws still releases the hold', () async {
    await expectLater(time.hold<void>(() async => throw StateError('start failed')), throwsStateError);
    expect(calls, ['begin', 'end']);
    // And the next hold asks afresh.
    await time.hold(() async {});
    expect(calls, ['begin', 'end', 'begin', 'end']);
  });

  test('a platform that cannot give time never stops the work', () async {
    // An older Runner without the method throws MissingPluginException; a
    // connect must not fail over a missing grace period.
    final refusing = BackgroundTime(
      begin: () async => throw Exception('no such method'),
      end: () async => throw Exception('no such method'),
    );
    expect(await refusing.hold(() async => 'connected'), 'connected');
  });
}
