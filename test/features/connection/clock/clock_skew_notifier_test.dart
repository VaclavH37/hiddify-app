import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/clock/model/clock_skew.dart';
import 'package:hiddify/features/connection/clock/notifier/clock_skew_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The notifier's timing: the failover ladder must see a sample the moment it
/// lands, while the state the home page watches follows after the current
/// Riverpod flush.
void main() {
  ClockSample fastBy(Duration ahead) {
    final now = DateTime.now().toUtc();
    return ClockSample.fromResponse(
      sentAt: now,
      receivedAt: now.add(const Duration(milliseconds: 100)),
      date: HttpDate.format(now.subtract(ahead)),
    )!;
  }

  test('a wrong clock explains a dead tunnel at once, and reaches the banner after a microtask', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(clockSkewNotifierProvider.notifier);

    notifier.sample(fastBy(const Duration(minutes: 2)));
    expect(notifier.explainsDeadTunnel(), isTrue);
    expect(container.read(clockSkewNotifierProvider), isNull, reason: 'not published inside the flush');

    await Future<void>.delayed(Duration.zero);
    expect(container.read(clockSkewNotifierProvider)?.skew?.inSeconds, inInclusiveRange(119, 121));
  });

  test('a right clock clears it, and a dismissal hides it until then', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(clockSkewNotifierProvider.notifier);

    notifier.sample(fastBy(const Duration(minutes: 2)));
    notifier.dismiss();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(clockSkewNotifierProvider)?.dismissed, isTrue);

    notifier.sample(fastBy(Duration.zero));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(clockSkewNotifierProvider), isNull);
    expect(notifier.explainsDeadTunnel(), isFalse);
  });

  test('a certificate dated as expired raises it without an offset', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(clockSkewNotifierProvider.notifier).certificateDatesRejected();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(clockSkewNotifierProvider), const ClockIssue(skew: null));
  });
}
