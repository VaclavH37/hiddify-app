import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';

import 'package:hiddify/utils/custom_loggers.dart';

/// Re-applies the response type a request asked for, on every attempt.
///
/// `DioMixin.fetch<T>` does not merely read `responseType` — it OVERWRITES it
/// on the RequestOptions from the generic type argument (dio_mixin.dart:379):
/// `String` becomes `plain`, and anything else that is not `dynamic` becomes
/// `json`. `dio_smart_retry` re-issues a failed request as `dio.fetch<void>`,
/// and `void` is neither, so a retry silently rewrites the request to `json` —
/// on the same RequestOptions instance the first attempt used.
///
/// A subscription body served as `application/json` then comes back decoded to
/// a Map, and the `Response<String>` cast in `assureResponse` fails with
/// `_Map<String, dynamic> is not a subtype of type 'String?'`. That surfaces as
/// `DioException [unknown]` — a type error wearing a network error's clothes,
/// which is how it read as a broken token on the import path.
///
/// It needs BOTH a retry and a JSON-typed body, so it fires intermittently and
/// only against servers that content-type their responses that way. Ours does.
class _ResponseTypeGuard extends Interceptor {
  static const key = 'rayn_response_type';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final intended = options.extra[key];
    if (intended is ResponseType) {
      options.responseType = intended;
    }
    handler.next(options);
  }
}

class DioHttpClient with InfraLogger {
  final Map<String, Dio> _dio = {};
  DioHttpClient({required Duration timeout, required this.userAgent, required bool debug}) {
    for (var mode in ["proxy", "direct", "both"]) {
      _dio[mode] = Dio(
        BaseOptions(
          connectTimeout: timeout,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: {"User-Agent": userAgent},
        ),
      );
      // MUST stay ahead of RetryInterceptor, and must not be removed as
      // cosmetic — see the class comment. Without it a retried subscription
      // fetch decodes as JSON and the import fails with a type-cast error.
      _dio[mode]!.interceptors.add(_ResponseTypeGuard());
      _dio[mode]!.interceptors.add(
        RetryInterceptor(
          dio: _dio[mode]!,
          retryDelays: [
            const Duration(seconds: 1),
            if (mode != "proxy") ...[const Duration(seconds: 2), const Duration(seconds: 3)],
          ],
        ),
      );

      _dio[mode]!.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (url) {
            if (mode == "proxy") {
              return "PROXY localhost:$port";
            } else if (mode == "direct") {
              return "DIRECT";
            } else {
              return "PROXY localhost:$port; DIRECT";
            }
          };
          return client;
        },
      );
    }

    if (debug) {
      // _dio.interceptors.add(LoggyDioInterceptor(requestHeader: true));
    }
  }

  int port = 0;

  String userAgent;
  // bool isPortOpen(String host, int port, {Duration timeout = const Duration(milliseconds: 200)}) async{
  //   try {
  //     Socket.connect(host, port, timeout: timeout).then((socket) {
  //       socket.destroy();
  //     });
  //     return true;
  //   } on SocketException catch (_) {
  //     return false;
  //   } catch (_) {
  //     return false;
  //   }
  // }
  Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      await socket.close();
      return true;
    } on SocketException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  void setProxyPort(int port) {
    this.port = port;
    loggy.debug("setting proxy port: [$port]");
  }

  Future<Response<T>> get<T>(
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
        ? "both"
        : "direct";
    final dio = _dio[mode]!;

    return dio.get<T>(
      url,
      cancelToken: cancelToken,
      options: _options(url, userAgent: userAgent, credentials: credentials),
    );
  }

  /// Fetches a response body into memory as text.
  ///
  /// Used for subscription bodies, which must never be written to disk: they
  /// carry the hub IP, per-user UUIDs and Reality shortIDs, and the whole point
  /// of sealing `configs/<id>.enc` is undone if the plaintext lands in a temp
  /// file first — a file that survives a hard kill, because its cleanup is a
  /// `finally` block.
  ///
  /// `ResponseType.plain` is required: with the default `json`, dio decodes any
  /// `application/json` response into a Map and the `Response<String>` cast
  /// throws — which would look like a network failure rather than a type error.
  Future<Response<String>> getText(
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
        ? "both"
        : "direct";
    return _dio[mode]!.get<String>(
      url,
      cancelToken: cancelToken,
      options: _options(
        url,
        userAgent: userAgent,
        credentials: credentials,
        responseType: ResponseType.plain,
      ),
    );
  }

  // There is deliberately no `download(url, path)` here any more. Its only
  // callers were the subscription fetch paths, and streaming a response body
  // straight to disk is exactly what the at-rest encryption work removed. If a
  // future feature genuinely needs a file, write it through the cipher rather
  // than reinstating a raw one.

  Options _options(
    String url, {
    String? userAgent,
    ({String username, String password})? credentials,
    ResponseType? responseType,
  }) {
    final uri = Uri.parse(url);

    String? userInfo;
    if (credentials != null) {
      userInfo = "${credentials.username}:${credentials.password}";
    } else if (uri.userInfo.isNotEmpty) {
      userInfo = uri.userInfo;
    }

    String? basicAuth;
    if (userInfo != null) {
      basicAuth = "Basic ${base64.encode(utf8.encode(userInfo))}";
    }

    return Options(
      responseType: responseType,
      // Restated in `extra` because dio overwrites `responseType` on the
      // RequestOptions itself; this is the copy _ResponseTypeGuard restores.
      extra: responseType == null ? null : {_ResponseTypeGuard.key: responseType},
      headers: {
        if (userAgent != null) "User-Agent": userAgent,
        if (basicAuth != null) "authorization": basicAuth,
        // "Accept": "application/json",
        // "Content-Type": "application/json",
      },
    );
  }
}
