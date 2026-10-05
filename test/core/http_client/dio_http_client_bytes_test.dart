import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';

/// [DioHttpClient.getBytes] fetches rule-sets from the mirror into memory, and
/// [DioHttpClient.downloadToFile] streams the Windows installer to disk. Both
/// must return the body byte for byte, and must stop reading the moment a body
/// passes the caller's cap, declared or not. A download that does not finish
/// leaves no file behind.
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

  group('downloadToFile', () {
    late Directory dir;
    late File target;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('rayn_download_test');
      target = File('${dir.path}/RaynVPN-setup.exe.part');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    final big = List<int>.generate(1024 * 1024, (i) => (i * 7) % 256);

    void chunked(HttpResponse res) {
      res.contentLength = big.length;
      for (var i = 0; i < big.length; i += 64 * 1024) {
        res.add(big.sublist(i, i + 64 * 1024));
      }
    }

    test('writes the body byte for byte and reports progress up to its length', () async {
      script = [chunked];
      final progress = <int>[];
      final written = await client().downloadToFile(url(), target, maxBytes: big.length, onProgress: progress.add);

      expect(written, big.length);
      expect(target.readAsBytesSync(), big);
      expect(progress, isNotEmpty);
      expect(progress.last, big.length);
      expect(progress, orderedEquals([...progress]..sort()));
    });

    test('a declared length over the cap is refused and nothing is written', () async {
      script = [chunked];
      await expectLater(
        client().downloadToFile(url(), target, maxBytes: big.length - 1),
        throwsA(isA<ResponseTooLargeException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('an undeclared body passing the cap is refused and the partial file deleted', () async {
      script = [
        (res) {
          for (var i = 0; i < big.length; i += 64 * 1024) {
            res.add(big.sublist(i, i + 64 * 1024));
          }
        },
      ];
      await expectLater(
        client().downloadToFile(url(), target, maxBytes: 100 * 1024),
        throwsA(isA<ResponseTooLargeException>()),
      );
      expect(target.existsSync(), isFalse);
    });

    test('a cancel part-way leaves no file', () async {
      script = [chunked];
      final token = CancelToken();
      await expectLater(
        client().downloadToFile(
          url(),
          target,
          maxBytes: big.length,
          cancelToken: token,
          onProgress: (_) => token.cancel(),
        ),
        throwsA(anything),
      );
      expect(target.existsSync(), isFalse);
    });

    test('an error status writes nothing', () async {
      script = [
        (res) {
          res.statusCode = 404;
          res.write('not found');
        },
      ];
      await expectLater(client().downloadToFile(url(), target, maxBytes: big.length), throwsA(anything));
      expect(target.existsSync(), isFalse);
    });
  });
}
