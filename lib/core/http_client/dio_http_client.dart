import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// A response body larger than the caller allowed. The connection is dropped
/// once the cap is passed, so a hostile or broken server cannot fill memory.
class ResponseTooLargeException implements Exception {
  const ResponseTooLargeException(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'response larger than $maxBytes bytes';
}

class DioHttpClient with InfraLogger {
  final Map<String, Dio> _dio = {};
  DioHttpClient({required Duration timeout, required this.userAgent, required bool debug}) {
    for (final mode in ["proxy", "direct", "both"]) {
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
      // ONE retry, on every mode. `retries` is the knob, NOT `retryDelays`.
      //
      // An earlier attempt at this passed only `retryDelays: [1s]` and left
      // `retries` at its default of 3. RetryInterceptor gates on
      // `attempt <= retries` and reuses the LAST delay when retries outnumber
      // delays (retry_interceptor.dart:62-63, 151-153), so that changed four
      // attempts spaced 1/2/3s into four attempts spaced 1/1/1s. Field logs
      // measured the result precisely: 66.0s per host became 63.0s. Three
      // seconds, all of it delay.
      //
      // `both` and `direct` used to get three, which costs 4 attempts x 15s
      // plus 1+2+3s of delay = 66s per host before a failure is reported. That
      // is the budget, and a blocked hub spends all of it: on iOS and desktop
      // the app's own traffic is captured by the tun, so BOTH legs of `both`
      // die at the hub — and then `_downloadWithFailover` pays the same 66s
      // again against the fallback middleware host, which is behind the same
      // dead tunnel. Field logs measured exactly 66.0s per host, 132s total,
      // before the reachability ladder even began.
      //
      // Two minutes of silence is long enough that a user reasonably concludes
      // the app has hung and toggles the VPN — which, as the iOS capture shows,
      // lands the completed refresh on a restarting core and destroys it. One
      // retry still absorbs a single transient blip and halves the wait.
      //
      // It shortens the ladder's own probes too: those run in `proxy` mode and
      // were paying the same four attempts, ~43s each in the iOS capture.
      //
      // NOT paired with skipping the fallback host: trying it is the only way
      // to tell a dead tunnel from a dead primary middleware host, and skipping
      // it would disable `fallback-url` in exactly the case it exists for.
      _dio[mode]!.interceptors.add(
        RetryInterceptor(dio: _dio[mode]!, retries: 1, retryDelays: const [Duration(seconds: 1)]),
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
    bool directOnly = false,
    Map<String, String>? extraHeaders,
  }) async {
    assert(!(proxyOnly && directOnly), "pick one leg, or neither");
    final mode = proxyOnly
        ? "proxy"
        : directOnly
        ? "direct"
        : await isPortOpen("127.0.0.1", port)
        ? "both"
        : "direct";
    return _fetchText(
      mode,
      url,
      cancelToken: cancelToken,
      userAgent: userAgent,
      credentials: credentials,
      extraHeaders: extraHeaders,
    );
  }

  Future<Response<String>> _fetchText(
    String mode,
    String url, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    Map<String, String>? extraHeaders,
  }) => _dio[mode]!.get<String>(
    url,
    cancelToken: cancelToken,
    options: _options(
      url,
      userAgent: userAgent,
      credentials: credentials,
      responseType: ResponseType.plain,
      extraHeaders: extraHeaders,
    ),
  );

  // There is deliberately no `download(url, path)` here any more. Its only
  // callers were the subscription fetch paths, and streaming a response body
  // straight to disk is exactly what the at-rest encryption work removed. If a
  // future feature genuinely needs a file, write it through the cipher rather
  // than reinstating a raw one.

  /// Fetches a response body into memory as bytes, refusing more than
  /// [maxBytes]: a declared length over the cap fails before the body is read,
  /// and an undeclared one fails as soon as it passes the cap.
  ///
  /// This is not the removed `download()` above. That streamed secret
  /// subscription bodies to disk. This is for public data, the rule-set mirror,
  /// which the caller verifies against a digest before writing it anywhere,
  /// and it never touches disk itself.
  Future<Uint8List> getBytes(
    String url, {
    required int maxBytes,
    CancelToken? cancelToken,
    bool proxyOnly = false,
  }) async {
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
        ? "both"
        : "direct";
    final response = await _dio[mode]!.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: _options(url, responseType: ResponseType.stream),
    );
    final body = response.data!;
    if (body.contentLength > maxBytes) {
      await body.stream.listen(null).cancel();
      throw ResponseTooLargeException(maxBytes);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) throw ResponseTooLargeException(maxBytes);
    }
    return bytes.takeBytes();
  }

  /// Streams a response body into [target], refusing more than [maxBytes] the
  /// way [getBytes] does, and reports progress as it goes. Any failure,
  /// including a cancel, deletes what was written. Returns the byte count.
  ///
  /// Not the removed `download()` either: that wrote secret subscription
  /// bodies. This writes the Windows updater's installer, a public file that
  /// the caller checks against the size and digest in its signed manifest
  /// before anything runs it.
  Future<int> downloadToFile(
    String url,
    File target, {
    required int maxBytes,
    CancelToken? cancelToken,
    bool proxyOnly = false,
    void Function(int received)? onProgress,
  }) async {
    final mode = proxyOnly
        ? "proxy"
        : await isPortOpen("127.0.0.1", port)
        ? "both"
        : "direct";
    final response = await _dio[mode]!.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: _options(url, responseType: ResponseType.stream),
    );
    final body = response.data!;
    if (body.contentLength > maxBytes) {
      await body.stream.listen(null).cancel();
      throw ResponseTooLargeException(maxBytes);
    }
    final sink = target.openWrite();
    var received = 0;
    var complete = false;
    try {
      await for (final chunk in body.stream) {
        received += chunk.length;
        if (received > maxBytes) throw ResponseTooLargeException(maxBytes);
        sink.add(chunk);
        onProgress?.call(received);
      }
      await sink.flush();
      complete = true;
    } finally {
      try {
        await sink.close();
      } on FileSystemException {
        complete = false;
      }
      if (!complete && target.existsSync()) target.deleteSync();
    }
    return received;
  }

  Options _options(
    String url, {
    String? userAgent,
    ({String username, String password})? credentials,
    ResponseType? responseType,
    Map<String, String>? extraHeaders,
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
        ...?extraHeaders,
        // "Accept": "application/json",
        // "Content-Type": "application/json",
      },
    );
  }
}
