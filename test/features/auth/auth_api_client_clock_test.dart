import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/auth/login/data/auth_api_client.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/features/connection/clock/model/clock_skew.dart';

/// The account API hands every answer's `Date` to the "device time is wrong"
/// check, refusals included: a 4xx is still our server's clock.
void main() {
  late HttpServer server;
  late int status;
  late DateTime serverClock;

  setUp(() async {
    status = 200;
    serverClock = DateTime.now().toUtc().subtract(const Duration(minutes: 2));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final res = request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json;
      res.headers.date = serverClock;
      res.write(jsonEncode({'ok': true}));
      await res.close();
    });
  });

  tearDown(() => server.close(force: true));

  AuthApiClient client(ClockEvidenceSink sink) =>
      AuthApiClient(baseUrl: 'http://127.0.0.1:${server.port}', userAgent: 'test', clockEvidence: sink);

  test('a success hands its Date over', () async {
    final sink = _RecordingClockSink();
    await client(sink).get('/api/public/account/subscription');
    expect(sink.samples.single.skew.inSeconds, inInclusiveRange(119, 121));
  });

  test('so does a refusal', () async {
    status = 401;
    final sink = _RecordingClockSink();
    await expectLater(client(sink).get('/api/public/account/subscription'), throwsA(isA<AuthApiException>()));
    expect(sink.samples.single.skew.inSeconds, inInclusiveRange(119, 121));
  });

  test('no sink, no bother', () async {
    final api = AuthApiClient(baseUrl: 'http://127.0.0.1:${server.port}', userAgent: 'test');
    expect(await api.get('/api/public/account/subscription'), {'ok': true});
  });
}

class _RecordingClockSink implements ClockEvidenceSink {
  final samples = <ClockSample>[];

  @override
  void sample(ClockSample sample) => samples.add(sample);

  @override
  void certificateDatesRejected() {}
}
