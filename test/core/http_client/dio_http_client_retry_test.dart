import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';

/// Regression test for the `_Map<String, dynamic> is not a subtype of String?`
/// cast error that intermittently failed profile import.
///
/// `DioMixin.fetch<T>` overwrites `RequestOptions.responseType` from its
/// generic argument (dio_mixin.dart:379). `dio_smart_retry` re-issues a failed
/// request as `dio.fetch<void>`, and `void` is neither `dynamic` nor `String`,
/// so the retry rewrote the request to `ResponseType.json` — losing the
/// `plain` that [DioHttpClient.getText] sets, on the same RequestOptions
/// instance the first attempt used.
///
/// It needs BOTH a retry and a JSON content type to bite, which is why it
/// looked random. The third test is the one that fails without the fix; the
/// second exists to prove the retry itself is not the trigger.
void main() {
  late HttpServer server;
  late List<void Function(HttpResponse)> script;
  var served = 0;

  setUp(() async {
    served = 0;
    script = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final index = served < script.length ? served : script.length - 1;
      served++;
      script[index](request.response);
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  String url() => 'http://127.0.0.1:${server.port}/sub';

  DioHttpClient client() => DioHttpClient(
    timeout: const Duration(seconds: 5),
    userAgent: 'test',
    debug: false,
  );

  void json(HttpResponse res, int status, Object body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
  }

  void text(HttpResponse res, int status, String body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.text;
    res.write(body);
  }

  test('a plain 200 with a JSON content type stays a String', () async {
    script = [(res) => json(res, 200, {'error_code': 4010})];
    final rs = await client().getText(url());
    expect(rs.data, isA<String>());
  });

  test('a retried request still yields a String body', () async {
    script = [
      // First attempt: a retryable status carrying a JSON error body.
      (res) => json(res, 503, {'message': 'slow down'}),
      // Retry: the real subscription body.
      (res) => text(res, 200, 'vless://real-subscription-body'),
    ];
    final rs = await client().getText(url());
    expect(served, 2, reason: 'the retry interceptor should have re-issued once');
    expect(rs.data, isA<String>());
    expect(rs.data, 'vless://real-subscription-body');
  });

  test('a retry that itself returns JSON still yields a String body', () async {
    script = [
      (res) => json(res, 503, {'message': 'slow down'}),
      (res) => json(res, 200, {'error_code': 4010, 'new-url': 'https://example.test/x'}),
    ];
    final rs = await client().getText(url());
    expect(served, 2);
    expect(rs.data, isA<String>());
  });
}
