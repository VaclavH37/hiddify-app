import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/model/url_test_snapshot.dart';
import 'package:hiddify/hiddifycore/generated/google/protobuf/timestamp.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// The fast path reads what is in use from the selector's chosen entry, and
/// judges the hub by every location in the full list.
void main() {
  final at = DateTime.utc(2026, 10, 18, 1, 47, 40);

  OutboundInfo info(String tag, int delay, {bool group = false}) =>
      OutboundInfo(tag: tag, urlTestDelay: delay, isGroup: group, urlTestTime: Timestamp.fromDateTime(at));

  // The selector as the core reports it in the full stream: the url-test group
  // it has chosen (carrying its chosen location's result), the balancer, and
  // every location.
  final selector = OutboundGroup(
    tag: 'select',
    selected: 'lowest',
    items: [
      info('lowest', 65535, group: true),
      info('balance', 180, group: true),
      info('EXIT-Los Angeles', 65535),
      info('EXIT-Tokyo', 180),
      info('direct §hide§', 20),
    ],
  );

  test('what is in use is the chosen entry, with its own result', () {
    final snapshot = urlTestSnapshotOf([selector]);
    expect(snapshot.selected, [(delay: 65535, testedAt: at)]);
  });

  test('every location once, without the groups or hidden outbounds', () {
    final snapshot = urlTestSnapshotOf([selector]);
    expect(snapshot.all, [(delay: 65535, testedAt: at), (delay: 180, testedAt: at)]);
  });

  test('a location listed by several groups counts once', () {
    final lowest = OutboundGroup(
      tag: 'lowest',
      selected: 'EXIT-Los Angeles',
      items: [info('EXIT-Los Angeles', 65535), info('EXIT-Tokyo', 180)],
    );
    final snapshot = urlTestSnapshotOf([selector, lowest]);
    expect(snapshot.all, hasLength(2));
    expect(snapshot.selected, hasLength(2));
  });

  test('an untested location reads as untested', () {
    final snapshot = urlTestSnapshotOf([
      OutboundGroup(
        tag: 'select',
        selected: 'EXIT-Tokyo',
        items: [OutboundInfo(tag: 'EXIT-Tokyo')],
      ),
    ]);
    expect(snapshot.all, [(delay: 0, testedAt: null)]);
  });

  test('no session: nothing in use and no locations', () {
    final snapshot = urlTestSnapshotOf(const []);
    expect(snapshot.selected, isEmpty);
    expect(snapshot.all, isEmpty);
  });
}
