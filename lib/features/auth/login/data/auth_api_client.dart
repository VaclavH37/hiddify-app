import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/auth/login/data/pow_solver.dart';
import 'package:hiddify/features/auth/login/model/auth_api_exception.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_api_client.g.dart';

@Riverpod(keepAlive: true)
AuthApiClient authApiClient(Ref ref) {
  return AuthApiClient(
    baseUrl: Constants.apiBaseUrl,
    userAgent: ref.watch(appInfoProvider).requireValue.userAgent,
  );
}

/// Thin JSON client for the account/auth API.
///
/// Deliberately separate from the shared [DioHttpClient]: that client only
/// does GET/download and can route through the local proxy when the tunnel is
/// up. The auth host must always be reached **DIRECT** (login runs with the VPN
/// off, and the API host must never be tunnelled), and we need JSON `POST` with
/// a `Bearer` header — none of which the shared client supports.
class AuthApiClient with InfraLogger {
  AuthApiClient({required String baseUrl, required String userAgent})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          contentType: Headers.jsonContentType,
          headers: {"User-Agent": userAgent},
          // We branch on status ourselves to build typed AuthApiExceptions.
          validateStatus: (_) => true,
        ),
      ) {
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        // Never tunnel the auth host through the VPN proxy.
        client.findProxy = (_) => "DIRECT";
        return client;
      },
    );
  }

  final Dio _dio;

  /// Fetch a fresh PoW challenge, solve it off the UI thread, and submit the
  /// gated request with `pow_challenge` / `pow_nonce` merged into [body].
  ///
  /// A challenge is single-use with a short TTL, so we fetch a fresh one for
  /// every gated request and never cache. On `403 "challenge verification
  /// failed"` we discard and retry the whole flow exactly once with a brand-new
  /// challenge (it may have expired or the difficulty changed).
  Future<Map<String, dynamic>> gatedPost(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    try {
      return await _gatedPostOnce(path, body, bearer: bearer);
    } on AuthApiException catch (e) {
      if (e.status == 403 && e.code == null) {
        loggy.debug("gated request rejected (challenge); retrying once with a fresh challenge");
        return await _gatedPostOnce(path, body, bearer: bearer);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _gatedPostOnce(
    String path,
    Map<String, dynamic> body, {
    String? bearer,
  }) async {
    final challenge = await post('/api/public/pow/challenge', const {});
    final nonce = await solvePow(challenge['challenge'] as String, challenge['difficulty'] as int);
    return post(path, {
      ...body,
      'pow_challenge': challenge['challenge'],
      'pow_nonce': nonce,
    }, bearer: bearer);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {String? bearer}) =>
      _request(() => _dio.post<dynamic>(path, data: body, options: _options(bearer)), path);

  Future<Map<String, dynamic>> get(String path, {String? bearer}) =>
      _request(() => _dio.get<dynamic>(path, options: _options(bearer)), path);

  Options _options(String? bearer) =>
      Options(headers: {if (bearer != null) "Authorization": "Bearer $bearer"});

  Future<Map<String, dynamic>> _request(Future<Response<dynamic>> Function() send, String path) async {
    final Response<dynamic> resp;
    try {
      resp = await send();
    } on DioException catch (e) {
      // Transport failure (timeout, connection refused, no route). The host is
      // unreachable — surfaced as a 0-status exception so callers can offer the
      // "paste your token instead" fallback. Never log bodies/credentials.
      loggy.debug("auth api transport failure on $path: ${e.type}");
      throw AuthApiException.unreachable(e.message ?? e.type.name);
    }

    final status = resp.statusCode ?? 0;
    final data = resp.data;
    final map = data is Map<String, dynamic> ? data : <String, dynamic>{};

    if (status >= 200 && status < 300) return map;

    throw AuthApiException(
      status: status,
      code: map['code'] as String?,
      message: (map['error'] as String?) ?? 'request failed',
      retryAfter: _retryAfter(resp.headers),
    );
  }

  Duration? _retryAfter(Headers headers) {
    final raw = headers.value('retry-after');
    if (raw == null) return null;
    final secs = int.tryParse(raw.trim());
    return secs == null ? null : Duration(seconds: secs);
  }
}
