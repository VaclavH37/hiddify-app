import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/utils/resubscribe_backoff.dart';

void main() {
  test('starts at 2 s and doubles up to 30 s', () {
    final backoff = ResubscribeBackoff();
    expect(
      [for (var i = 0; i < 7; i++) backoff.next().inSeconds],
      [2, 4, 8, 16, 30, 30, 30],
    );
  });

  test('reset goes back to the start', () {
    final backoff = ResubscribeBackoff()
      ..next()
      ..next()
      ..reset();
    expect(backoff.next(), const Duration(seconds: 2));
  });
}
