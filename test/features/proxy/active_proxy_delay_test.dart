import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The delay the connect orb, the location card and the IP routing check read:
/// this session's measurement, never one Riverpod kept from before a stop or a
/// reload.
void main() {
  final measured = AsyncData(OutboundInfo(tag: 'EXIT-Tokyo', urlTestDelay: 21));

  test("this session's measurement", () {
    expect(activeProxyDelay(measured), 21);
    expect(activeProxyDelay(AsyncData(OutboundInfo(tag: 'EXIT-Tokyo'))), 0);
  });

  test('not after the service stopped: the error still carries the old outbound', () {
    final stopped = const AsyncError<OutboundInfo>(ServiceNotRunning(), StackTrace.empty).copyWithPrevious(measured);
    expect(stopped.valueOrNull?.urlTestDelay, 21, reason: 'what the readers used to see');
    expect(activeProxyDelay(stopped), 0);
  });

  test('not while the stream reopens or the core restarts', () {
    for (final isRefresh in [true, false]) {
      final reloading = const AsyncLoading<OutboundInfo>().copyWithPrevious(measured, isRefresh: isRefresh);
      expect(reloading.valueOrNull?.urlTestDelay, 21, reason: 'what the readers used to see');
      expect(activeProxyDelay(reloading), 0, reason: 'isRefresh $isRefresh');
    }
  });

  test('nothing yet', () {
    expect(activeProxyDelay(const AsyncLoading()), 0);
  });
}
