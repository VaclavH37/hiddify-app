import 'package:flutter_test/flutter_test.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/hiddifycore/core_stream_errors.dart';

/// A failed core stream is reported at the severity it warrants: routine
/// absence quietly, a recovered connection reset as a warning, everything else
/// as an error.
void main() {
  // As logged twice at the 2026-10-18 failover on Windows.
  const reset = GrpcError.custom(
    StatusCode.unknown,
    'HTTP/2 error: Connection error: Connection is being forcefully terminated. (errorCode: 1)',
  );

  test('the background core not started yet is routine', () {
    expect(coreStreamErrorLevel('bgStatusListener', const GrpcError.unavailable()), CoreStreamErrorLevel.debug);
    expect(coreStreamErrorLevel('bgLogListener', const GrpcError.unavailable()), CoreStreamErrorLevel.debug);
  });

  test('the foreground core unavailable stays an error', () {
    expect(coreStreamErrorLevel('fgLogListener', const GrpcError.unavailable()), CoreStreamErrorLevel.error);
  });

  test('a connection reset is a warning, on either core', () {
    expect(coreStreamErrorLevel('fgLogListener', reset), CoreStreamErrorLevel.warning);
    expect(coreStreamErrorLevel('bgStatusListener', reset), CoreStreamErrorLevel.warning);
  });

  test('other failures stay errors', () {
    expect(coreStreamErrorLevel('fgLogListener', const GrpcError.unknown('core panicked')), CoreStreamErrorLevel.error);
    expect(coreStreamErrorLevel('fgLogListener', const GrpcError.internal('HTTP/2 error')), CoreStreamErrorLevel.error);
    expect(coreStreamErrorLevel('fgLogListener', StateError('client not built')), CoreStreamErrorLevel.error);
  });

  // One broadcaster per core process: a listener on each channel to the same
  // process logged every line twice (upstream 1685304f).
  group('log listeners', () {
    test('Android: the background listener is left out, the foreground one kept', () {
      expect(skipsLogListener('bg', sameChannel: false, sharesProcess: true), isTrue);
      expect(skipsLogListener('fg', sameChannel: false, sharesProcess: true), isFalse);
    });

    test('desktop: one channel, one listener', () {
      expect(skipsLogListener('bg', sameChannel: true, sharesProcess: false), isTrue);
      expect(skipsLogListener('fg', sameChannel: true, sharesProcess: false), isFalse);
    });

    test('iOS: the extension is its own process, so both are kept', () {
      expect(skipsLogListener('bg', sameChannel: false, sharesProcess: false), isFalse);
      expect(skipsLogListener('fg', sameChannel: false, sharesProcess: false), isFalse);
    });
  });
}
