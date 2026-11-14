import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/utils/laststeam.dart';

/// [LastStream] backs the mobile start wait (core_interface_mobile.dart): one
/// wait for the first status that settles the start, instead of polling.
void main() {
  late StreamController<int> source;
  late LastStream<int> last;

  setUp(() {
    source = StreamController<int>.broadcast();
    last = LastStream(source.stream);
  });

  tearDown(() async {
    await last.close();
    await source.close();
  });

  test('returns the latest value at once when it is accepted', () async {
    source.add(1);
    await pumpEventQueue();
    expect(await last.get(where: (v) => v == 1), 1);
  });

  test('skips a latest value it does not accept and waits for one it does', () async {
    source.add(1);
    await pumpEventQueue();
    final waiting = last.get(where: (v) => v.isEven);
    source
      ..add(3)
      ..add(4);
    expect(await waiting, 4);
  });

  test('a value completes only the waiters it satisfies', () async {
    final even = last.get(where: (v) => v.isEven);
    final odd = last.get(where: (v) => v.isOdd);
    var evenDone = false;
    unawaited(even.then((_) => evenDone = true));

    source.add(5);
    expect(await odd, 5);
    await pumpEventQueue();
    expect(evenDone, isFalse);

    source.add(6);
    expect(await even, 6);
  });

  test('without where, any value will do', () async {
    final waiting = last.get();
    source.add(7);
    expect(await waiting, 7);
  });

  test('times out when nothing accepted arrives, and forgets the waiter', () async {
    final waiting = last.get(timeout: const Duration(milliseconds: 20), where: (v) => v > 100);
    source.add(1);
    await expectLater(waiting, throwsA(isA<TimeoutException>()));
    // A later match has no waiter left to complete twice.
    source.add(101);
    await pumpEventQueue();
  });

  test('clean forgets the latest value', () async {
    source.add(1);
    await pumpEventQueue();
    last.clean();
    final waiting = last.get(timeout: const Duration(milliseconds: 20));
    await expectLater(waiting, throwsA(isA<TimeoutException>()));
  });

  test('close fails the waiters still pending', () async {
    final waiting = last.get(where: (v) => v > 100);
    await last.close();
    await expectLater(waiting, throwsA(isA<StateError>()));
  });
}
