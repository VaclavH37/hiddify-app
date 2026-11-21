import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';

/// The core's local mixed port asks for a password (local_proxy_auth.dart), so
/// the app's tunnel-only fetches must present it. This stands in for the port
/// and records what the HttpClient sends it.
void main() {
  late HttpServer proxy;
  late List<HttpHeaders> seen;

  setUp(() async {
    seen = [];
    proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    proxy.listen((request) async {
      seen.add(request.headers);
      request.response.write('through');
      await request.response.close();
    });
  });

  tearDown(() => proxy.close(force: true));

  DioHttpClient client(String? Function() password) =>
      DioHttpClient(timeout: const Duration(seconds: 5), userAgent: 'test', debug: false, localProxyPassword: password)
        ..setProxyPort(proxy.port);

  String basic(String password) => 'Basic ${base64Encode(utf8.encode('rayn:$password'))}';

  test('a tunnel-only fetch sends the local proxy password', () async {
    final response = await client(() => 'derived').get<String>('http://rayn.invalid/x', proxyOnly: true);

    expect(response.data, 'through');
    expect(seen.single.value(HttpHeaders.proxyAuthorizationHeader), basic('derived'));
  });

  test('no password, no Proxy-Authorization', () async {
    await client(() => null).get<String>('http://rayn.invalid/x', proxyOnly: true);

    expect(seen.single.value(HttpHeaders.proxyAuthorizationHeader), isNull);
  });

  // The mobile background secret rotates on every connect; a client built
  // once at startup must follow it.
  test('the password is read per request', () async {
    var password = 'first';
    final c = client(() => password);
    await c.get<String>('http://rayn.invalid/x', proxyOnly: true);
    password = 'second';
    await c.get<String>('http://rayn.invalid/y', proxyOnly: true);

    expect(seen.map((h) => h.value(HttpHeaders.proxyAuthorizationHeader)), [basic('first'), basic('second')]);
  });
}
