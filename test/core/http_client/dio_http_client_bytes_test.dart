import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';

/// [DioHttpClient.getBytes] fetches rule-sets from the mirror into memory. It
/// must return the body byte for byte, and must stop reading the moment a body
/// passes the caller's cap, declared or not.
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

  String url() => 'http://127.0.0.1:${server.port}/v1/files/x.srs';

  DioHttpClient client() => DioHttpClient(timeout: const Duration(seconds: 5), userAgent: 'test', debug: false);

  final body = List<int>.generate(4096, (i) => i % 256);

  void declared(HttpResponse res) {
    res.contentLength = body.length;
    res.add(body);
  }

  void undeclared(HttpResponse res) {
    for (var i = 0; i < body.length; i += 512) {
      res.add(body.sublist(i, i + 512));
    }
  }

  test('returns the body byte for byte', () async {
    script = [declared];
    expect(await client().getBytes(url(), maxBytes: body.length), body);
  });

  test('a body exactly at the cap is accepted, declared or not', () async {
    script = [undeclared];
    expect(await client().getBytes(url(), maxBytes: body.length), body);
  });

  test('a declared length over the cap is refused before the body is read', () async {
    script = [declared];
    await expectLater(client().getBytes(url(), maxBytes: body.length - 1), throwsA(isA<ResponseTooLargeException>()));
  });

  test('an undeclared body is refused once it passes the cap', () async {
    script = [undeclared];
    await expectLater(client().getBytes(url(), maxBytes: 1000), throwsA(isA<ResponseTooLargeException>()));
  });

  // The retry interceptor re-issues a request with its own type argument; the
  // response-type guard must keep it a byte stream rather than JSON.
  test('a retried request still yields the bytes', () async {
    script = [
      (res) {
        res.statusCode = 503;
        res.headers.contentType = ContentType.json;
        res.write('{"message":"slow down"}');
      },
      declared,
    ];
    expect(await client().getBytes(url(), maxBytes: body.length), body);
    expect(served, 2);
  });

  test('an error status is an error, not a body', () async {
    script = [
      (res) {
        res.statusCode = 404;
        res.write('not found');
      },
    ];
    await expectLater(client().getBytes(url(), maxBytes: body.length), throwsA(anything));
  });
}
