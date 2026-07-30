import 'dart:convert';
import 'dart:io';

import 'package:dartx/dartx.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';
import 'package:meta/meta.dart';

/// parse profile subscription url and headers for data
///
/// ***name parser hierarchy:***
/// - UserOverride.name
/// - `profile-title` header
/// - `content-disposition` header
/// - url fragment (example: `https://example.com/config#user`) -> name=`user`
/// - url filename extension (example: `https://example.com/config.json`) -> name=`config`
/// - if none of these methods return a non-blank string, switch(profileType)
/// - remote:  fallback to `Remote Profile`
/// - local: fallback to protocol, extracted from content by protocol()

/// A subscription URL recovered from a `new-url` / `fallback-url` response
/// header: the decrypted `https://` [url] to request, plus the raw
/// `rayn://import/<token>` string to persist alongside it.
///
/// Compare the [url], never the [sourceToken] — the cryptolink envelope is
/// randomised, so re-encrypting the same URL yields a different string every
/// time (RAYN-LINK-SYMMETRIC-MIGRATION.md §4).
typedef SubscriptionRotation = ({String url, String sourceToken});

class ProfileParser {
  static const infiniteTrafficThreshold = 920_233_720_368;
  static const infiniteTimeThreshold = 92_233_720_368;
  // Max `new-url` hops to follow in one resolve before giving up (defensive;
  // the API guarantees a renewed token never bounces back to "expired").
  static const _maxRotationHops = 3;
  static const allowedOverrideConfigs = [
    'connection-test-url',
    'direct-dns-address',
    'remote-dns-address',
    'tls-tricks',
    'dns',
    'route',
  ];
  static const allowedProfileHeaders = [
    'profile-title',
    'content-disposition',
    'subscription-userinfo',
    'profile-update-interval',
    'support-url',
    'profile-web-page-url',
    'enable-fragment',
    'subscription-refill-date',
    // Subscription-management metadata surfaced on Settings → Account. Kept in
    // `populatedHeaders` (persisted) so it's available on every auth path,
    // including token-import users who have no account-API session.
    'subscription-billing-period',
    'subscription-payment-provider',
    'subscription-manage-url',
  ];

  final Ref _ref;
  final DioHttpClient _httpClient;

  static final _log = Loggy('profile_parser');

  ProfileParser({required Ref ref, required DioHttpClient httpClient}) : _ref = ref, _httpClient = httpClient;
  TaskEither<ProfileFailure, ProfileEntriesCompanion> addLocal({
    required String id,
    required String content,
    required String tempFilePath,
    required UserOverride? userOverride,
  }) {
    return TaskEither.tryCatch(() async {
          await expandRemoteLinesInParallel(
            tempFilePath: tempFilePath,
            httpClient: _httpClient,
            cancelToken: CancelToken(),
            ref: _ref,
          );
        }, (_, __) => ProfileFailure.unexpected())
        .flatMap((_) => TaskEither.fromEither(populateHeaders(content: content)))
        .flatMap(
          (populatedHeaders) => TaskEither.fromEither(
            parse(
              tempFilePath: tempFilePath,
              profile: ProfileEntity.local(
                id: id,
                active: true,
                name: '',
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: populatedHeaders,
              ),
            ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
          ),
        );
  }

  TaskEither<ProfileFailure, ProfileEntriesCompanion> addRemote({
    required String id,
    required String url,
    required String tempFilePath,
    required UserOverride? userOverride,
    String? sourceToken,
    CancelToken? cancelToken,
  }) => _resolveDownload(url, sourceToken, tempFilePath, cancelToken).flatMap((resolved) {
    final fallback = extractFallback(resolved.headers);
    if (fallback != null) {
      _log.info('capturing fallback URL on import (host: ${Uri.tryParse(fallback.url)?.host ?? "?"})');
    }
    return TaskEither.fromEither(
      populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: resolved.headers),
    ).flatMap(
      (populatedHeaders) => TaskEither.fromEither(
        parse(
          tempFilePath: tempFilePath,
          profile: ProfileEntity.remote(
            id: id,
            active: true,
            name: '',
            // `_resolveDownload` already followed any `new-url`, so these are
            // the renewed token's url/source when a rotation occurred.
            url: resolved.url,
            lastUpdate: DateTime.now(),
            userOverride: userOverride,
            populatedHeaders: populatedHeaders,
            sourceToken: resolved.sourceToken,
            fallbackUrl: fallback?.url,
            fallbackSourceToken: fallback?.sourceToken,
          ),
        ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected)),
      ),
    );
  });

  TaskEither<ProfileFailure, ProfileEntriesCompanion> updateRemote({
    required RemoteProfileEntity rp,
    required String tempFilePath,
    CancelToken? cancelToken,
  }) => _downloadWithFailover(rp, tempFilePath, cancelToken).flatMap((resolved) {
    var rotated = rp;
    // `_resolveDownload` already followed any `new-url`; persist the resulting
    // token when it changed.
    if (resolved.sourceToken != rp.sourceToken) {
      _log.info('rotating subscription URL on refresh (new host: ${Uri.tryParse(resolved.url)?.host ?? "?"})');
      rotated = rotated.copyWith(url: resolved.url, sourceToken: resolved.sourceToken);
    }
    final fallback = extractFallback(resolved.headers);
    // Same as the rotation guard above: compare decrypted URLs, never cryptolink
    // strings, or this rewrites both columns on every refresh (§4).
    if (fallback != null && fallback.url != rp.fallbackUrl) {
      _log.info('updating fallback URL on refresh (host: ${Uri.tryParse(fallback.url)?.host ?? "?"})');
      rotated = rotated.copyWith(fallbackUrl: fallback.url, fallbackSourceToken: fallback.sourceToken);
    }
    return TaskEither.fromEither(
      populateHeaders(content: File(tempFilePath).readAsStringSync(), remoteHeaders: resolved.headers),
    ).flatMap(
      (populatedHeaders) => TaskEither.fromEither(
        parse(
          tempFilePath: tempFilePath,
          profile: rotated.copyWith(populatedHeaders: populatedHeaders),
        ).flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected)),
      ),
    );
  });

  Either<ProfileFailure, ProfileEntriesCompanion> offlineUpdate({
    required ProfileEntity profile,
    required String tempFilePath,
  }) => profile
      .map(
        remote: (rp) => parse(profile: rp, tempFilePath: tempFilePath),
        local: (lp) => parse(tempFilePath: tempFilePath, profile: lp),
      )
      .flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected));

  TaskEither<ProfileFailure, Map<String, dynamic>> _downloadProfile(
    String url,
    String tempFilePath,
    CancelToken? cancelToken,
  ) => TaskEither.tryCatch(() async {
    // if (url.startsWith("http://"))
    //   throw const ProfileFailure.invalidUrl('HTTP is not supported. Please use HTTPS for secure connection.');

    final rs = await _httpClient
        .download(
          url.trim(),
          tempFilePath,
          cancelToken: cancelToken,
          userAgent: _ref.read(appInfoProvider).requireValue.subscriptionUserAgent,
        )
        .catchError((err) {
          if (CancelToken.isCancel(err as DioException)) {
            throw const ProfileFailure.cancelByUser('HTTP request for getting profile content canceled by user.');
          }
          throw err;
        });
    await expandRemoteLinesInParallel(
      tempFilePath: tempFilePath,
      httpClient: _httpClient,
      cancelToken: cancelToken ?? CancelToken(),
      ref: _ref,
    );
    // fixing headers before return
    return rs.headers.map.map((key, value) {
      if (value.length == 1) return MapEntry(key, value.first);
      return MapEntry(key, value);
    });
  }, (err, st) => err is ProfileFailure ? err : ProfileFailure.unexpected(err, st));

  /// One subscription request that follows `new-url` token rotation to the
  /// terminal response (see [Confirmed decisions] in the plan). Returns the
  /// terminal `headers` plus the `url`/`sourceToken` that produced it (the
  /// renewed token when a `new-url` was followed). A terminal `4010` envelope
  /// with no (further) `new-url` is a lapsed subscription →
  /// [ProfileFailure.subscriptionExpired]. Capped at [_maxRotationHops].
  TaskEither<ProfileFailure, ({Map<String, dynamic> headers, String url, String? sourceToken})> _resolveDownload(
    String url,
    String? sourceToken,
    String tempFilePath,
    CancelToken? cancelToken, {
    int depth = 0,
  }) => _downloadProfile(url, tempFilePath, cancelToken).flatMap((headers) {
    final rotation = extractRotation(headers);
    // Compare the DECRYPTED url, not the cryptolink: the envelope is randomised,
    // so the same URL re-encrypts to a different string on every response and a
    // string comparison would follow a "rotation" on every single refresh (§4).
    if (rotation != null && rotation.url != url && depth < _maxRotationHops) {
      _log.info(
        'following `new-url` to renewed token (hop ${depth + 1}, host: ${Uri.tryParse(rotation.url)?.host ?? "?"})',
      );
      return _resolveDownload(rotation.url, rotation.sourceToken, tempFilePath, cancelToken, depth: depth + 1);
    }
    if (isExpiredEnvelope(File(tempFilePath).readAsStringSync())) {
      _log.warning('subscription token expired with no renewal available');
      return TaskEither<ProfileFailure, ({Map<String, dynamic> headers, String url, String? sourceToken})>.left(
        const ProfileFailure.subscriptionExpired(),
      );
    }
    return TaskEither.right((headers: headers, url: url, sourceToken: sourceToken));
  });

  /// Wraps [_resolveDownload] with the fallback-URL failover policy. Used by
  /// [updateRemote] only — initial imports have no stored fallback yet.
  ///
  /// Failover triggers on any [ProfileFailure] from the primary except
  /// [ProfileCancelByUserFailure] (user intent) and
  /// [ProfileSubscriptionExpiredFailure] (an account state — the fallback host
  /// would return the same `4010`, so we surface the lapse instead).
  TaskEither<ProfileFailure, ({Map<String, dynamic> headers, String url, String? sourceToken})> _downloadWithFailover(
    RemoteProfileEntity rp,
    String tempFilePath,
    CancelToken? cancelToken,
  ) => TaskEither(() async {
    final primary = await _resolveDownload(rp.url, rp.sourceToken, tempFilePath, cancelToken).run();
    final primaryFailure = primary.fold<ProfileFailure?>((l) => l, (_) => null);
    if (primaryFailure == null) return primary;
    if (primaryFailure is ProfileCancelByUserFailure) return primary;
    if (primaryFailure is ProfileSubscriptionExpiredFailure) return primary;
    final fallback = rp.fallbackUrl;
    if (fallback == null || fallback.isEmpty) return primary;
    _log.info(
      'primary subscription URL failed (${Uri.tryParse(rp.url)?.host ?? "?"}); '
      'attempting fallback (${Uri.tryParse(fallback)?.host ?? "?"})',
    );
    final secondary = await _resolveDownload(fallback, rp.fallbackSourceToken, tempFilePath, cancelToken).run();
    final secondaryFailure = secondary.fold<ProfileFailure?>((l) => l, (_) => null);
    if (secondaryFailure == null) {
      _log.info('fallback subscription URL succeeded');
      return secondary;
    }
    if (secondaryFailure is ProfileCancelByUserFailure) return secondary;
    _log.warning('fallback URL also failed; surfacing original primary failure');
    return primary;
  });

  /// Reads the optional `new-url` rotation header on a subscription response,
  /// validates it parses as a `rayn://import/<token>` deep link, and decrypts
  /// to recover the underlying https URL. Returns the parsed link or null if
  /// the header is absent or invalid for any reason — callers fall through to
  /// using the existing URL/token unchanged.
  ///
  /// `result.url` is the decrypted https URL; `result.name` carries the raw
  /// `rayn://import/<token>` string the caller persists as the new sourceToken.
  static SubscriptionRotation? extractRotation(Map<String, dynamic> headers) {
    final raw = headers['new-url'];
    final value = switch (raw) {
      final String s => s,
      final List l when l.isNotEmpty => l.first?.toString(),
      _ => null,
    };
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    switch (LinkParser.parse(trimmed)) {
      case RaynLinkOk(:final url):
        return (url: url, sourceToken: trimmed);
      case RaynLinkUnsupportedVersion(:final version):
        // Loud: the backend has moved past what this build can read, so we will
        // silently stop following rotations until the app is updated.
        _log.error(
          '`new-url` uses cryptolink version 0x${version.toRadixString(16)} — app update required',
        );
        return null;
      case RaynLinkInvalid(:final reason):
        _log.warning('rotation header `new-url` rejected ($reason)');
        return null;
    }
  }

  /// Reads the optional `fallback-url` response header on a subscription
  /// response, validates it parses as `rayn://import/<token>`, and decrypts
  /// to recover the underlying https URL. Returns the parsed link or null
  /// if the header is absent or invalid for any reason — callers fall
  /// through to keeping the existing fallback unchanged.
  ///
  /// `result.url` is the decrypted https URL; `result.name` carries the raw
  /// `rayn://import/<token>` string the caller persists as `fallbackSourceToken`.
  static SubscriptionRotation? extractFallback(Map<String, dynamic> headers) {
    final raw = headers['fallback-url'];
    final value = switch (raw) {
      final String s => s,
      final List l when l.isNotEmpty => l.first?.toString(),
      _ => null,
    };
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    switch (LinkParser.parse(trimmed)) {
      case RaynLinkOk(:final url):
        return (url: url, sourceToken: trimmed);
      case RaynLinkUnsupportedVersion(:final version):
        _log.error(
          '`fallback-url` uses cryptolink version 0x${version.toRadixString(16)} — app update required',
        );
        return null;
      case RaynLinkInvalid(:final reason):
        _log.warning('fallback header `fallback-url` rejected ($reason)');
        return null;
    }
  }

  /// True when [body] is a token-expired envelope — the JSON
  /// `{"success":false,"error_code":4010,…}` the MW subscription API returns
  /// (HTTP 200) for an expired token. A normal sing-box config is JSON without
  /// `error_code`; non-JSON bodies are configs of other formats → false.
  /// Only meaningful on the terminal response: a `4010` carrying a `new-url`
  /// is followed before this check (see [_resolveDownload]).
  static bool isExpiredEnvelope(String body) {
    try {
      final decoded = jsonDecode(body.trim());
      if (decoded is! Map) return false;
      final code = decoded['error_code'];
      return code == 4010 || code == '4010';
    } catch (_) {
      return false;
    }
  }

  Future<void> expandRemoteLinesInParallel({
    required String tempFilePath,
    required DioHttpClient httpClient,
    required CancelToken cancelToken,
    required Ref ref,
    int parallelism = 4,
  }) async {
    final content = await File(tempFilePath).readAsString();
    final lines = content.split('\n');

    final results = List<String?>.filled(lines.length, null);

    int index = 0;

    Future<void> worker() async {
      while (true) {
        if (cancelToken.isCancelled) return;

        final currentIndex = index++;
        if (currentIndex >= lines.length) return;

        final line = lines[currentIndex];

        // Non-URL
        if (!line.startsWith('http://') && !line.startsWith('https://')) {
          results[currentIndex] = line.trim();
          continue;
        }

        try {
          final tmpPath = '$tempFilePath.$currentIndex';

          await httpClient.download(
            line,
            tmpPath,
            cancelToken: cancelToken,
            userAgent: ref.read(appInfoProvider).requireValue.subscriptionUserAgent,
          );

          results[currentIndex] = (await File(tmpPath).readAsString()).trim();
        } catch (err) {
          if (err is DioException && CancelToken.isCancel(err)) {
            return;
          }
          results[currentIndex] = '';
        }
      }
    }

    // Start workers
    await Future.wait(List.generate(parallelism, (_) => worker()));

    if (results.any((e) => e != null)) {
      final newContent = results.join("\n");
      await File(tempFilePath).writeAsString(newContent);
    }
  }

  static Either<ProfileFailure, Map<String, dynamic>> populateHeaders({
    required String content,
    Map<String, dynamic>? remoteHeaders,
  }) => Either.tryCatch(() {
    final contentHeaders = _parseHeadersFromContent(content);
    return _mergeAndValidateHeaders(contentHeaders, remoteHeaders ?? {});
  }, ProfileFailure.unexpected);

  static Map<String, dynamic> _mergeAndValidateHeaders(
    Map<String, dynamic> contentHeaders,
    Map<String, dynamic> remoteHeaders,
  ) {
    for (final entry in contentHeaders.entries) {
      if (!remoteHeaders.keys.contains(entry.key)) {
        remoteHeaders[entry.key] = entry.value;
      }
    }
    final headers = <String, dynamic>{};
    for (final entry in remoteHeaders.entries) {
      if (allowedProfileHeaders.contains(entry.key) && entry.value != null && entry.value.toString().isNotEmpty) {
        headers[entry.key] = entry.value;
      }
    }
    return headers;
  }

  static Map<String, dynamic> _parseHeadersFromContent(String content) {
    final headers = <String, dynamic>{};
    final content_ = safeDecodeBase64(content);
    final lines = content_.split("\n");
    final linesToProcess = lines.length < 10 ? lines.length : 10;
    for (int i = 0; i < linesToProcess; i++) {
      final line = lines[i];
      if (line.startsWith("#") || line.startsWith("//")) {
        final index = line.indexOf(':');
        if (index == -1) continue;
        final key = line.substring(0, index).replaceFirst(RegExp("^#|//"), "").trim().toLowerCase();
        final value = line.substring(index + 1).trim();
        headers[key] = value;
      }
    }
    return headers;
  }

  static SubscriptionInfo? _parseSubscriptionInfo(String subInfoStr) {
    final values = subInfoStr.split(';');
    final map = {for (final v in values) v.split('=').first.trim(): num.tryParse(v.split('=').second.trim())?.toInt()};
    if (map case {"upload": final upload?, "download": final download?, "total": final total, "expire": var expire}) {
      final total1 = (total == null || total == 0) ? infiniteTrafficThreshold + 1 : total;
      expire = (expire == null || expire == 0) ? infiniteTimeThreshold : expire;
      return SubscriptionInfo(
        upload: upload,
        download: download,
        total: total1,
        expire: DateTime.fromMillisecondsSinceEpoch(expire * 1000),
      );
    }
    return null;
  }

  @visibleForTesting
  static Either<ProfileFailure, ProfileEntity> parse({required String tempFilePath, required ProfileEntity profile}) =>
      Either.tryCatch(() {
        final headers = Map<String, dynamic>.from(profile.populatedHeaders ?? {});
        var name = '';
        if (profile.userOverride?.name case final String oName when oName.isNotEmpty) {
          name = oName;
        }

        if (headers['profile-title'] case final String titleHeader when name.isEmpty) {
          if (titleHeader.startsWith("base64:")) {
            name = utf8.decode(base64.decode(titleHeader.replaceFirst("base64:", "")));
          } else {
            name = titleHeader.trim();
          }
        }
        if (headers['content-disposition'] case final String contentDispositionHeader when name.isEmpty) {
          final regExp = RegExp('filename="([^"]*)"');
          final match = regExp.firstMatch(contentDispositionHeader);
          if (match != null && match.groupCount >= 1) {
            name = match.group(1) ?? '';
          }
        }
        if (profile case RemoteProfileEntity(:final url)) {
          if (Uri.parse(url).fragment case final fragment when name.isEmpty) {
            name = fragment;
          }
          if (url.split("/").lastOrNull case final part? when name.isEmpty) {
            final pattern = RegExp(r"\.(json|yaml|yml|txt)[\s\S]*");
            name = part.replaceFirst(pattern, "");
          }
        }
        if (name.isBlank) {
          switch (profile) {
            case RemoteProfileEntity():
              name = "Remote Profile";

            case LocalProfileEntity():
              name = protocol(File(tempFilePath).readAsStringSync());
          }
        }

        if (headers['enable-fragment'].toString() == 'true' || profile.userOverride?.enableFragment == true) {
          headers['tls-tricks'] = {'enable-fragment': true};
        }

        final isAutoUpdateDisable = profile.userOverride?.isAutoUpdateDisable ?? false;
        ProfileOptions? options;
        if (profile.userOverride?.updateInterval case final int updateInterval
            when updateInterval > 0 && !isAutoUpdateDisable) {
          options = ProfileOptions(updateInterval: Duration(hours: updateInterval));
        }
        if (headers['profile-update-interval'] case final String updateIntervalStr
            when options == null && !isAutoUpdateDisable) {
          final updateInterval = Duration(hours: int.parse(updateIntervalStr));
          options = ProfileOptions(updateInterval: updateInterval);
        }

        SubscriptionInfo? subInfo;
        if (headers['subscription-userinfo'] case final String subInfoStr) {
          subInfo = _parseSubscriptionInfo(subInfoStr);
        }

        if (subInfo != null) {
          if (headers['profile-web-page-url'] case final String profileWebPageUrl when isUrl(profileWebPageUrl)) {
            subInfo = subInfo.copyWith(webPageUrl: profileWebPageUrl);
          }
          if (headers['support-url'] case final String profileSupportUrl when isUrl(profileSupportUrl)) {
            subInfo = subInfo.copyWith(supportUrl: profileSupportUrl);
          }
          // `subscription-refill-date`: unix seconds for the next quota reset.
          // Treat 0/absent/garbage as "unknown" → leave null so the UI hides it.
          if (headers['subscription-refill-date'] case final String refillStr) {
            final refillSecs = int.tryParse(refillStr.trim());
            if (refillSecs != null && refillSecs > 0) {
              subInfo = subInfo.copyWith(refillDate: DateTime.fromMillisecondsSinceEpoch(refillSecs * 1000));
            }
          }
        }

        headers.removeWhere(
          (key, value) => !allowedOverrideConfigs.contains(key) || value == null || value.toString().isEmpty,
        );

        final profileOverrideStr = jsonEncode({for (final key in headers.keys) key: headers[key]});

        return profile.map(
          remote: (rp) => rp.copyWith(
            name: name,
            lastUpdate: DateTime.now(),
            options: options,
            subInfo: subInfo,
            profileOverride: profileOverrideStr,
          ),
          local: (lp) => lp.copyWith(name: name, lastUpdate: DateTime.now(), profileOverride: profileOverrideStr),
        );
      }, ProfileFailure.unexpected);

  static String protocol(String content) {
    if (content.contains("[Interface]")) {
      return ProxyType.wireguard.label;
    }
    final lines = content.split('\n');
    String? name;
    for (final line in lines) {
      final uri = Uri.tryParse(line);
      if (uri == null) continue;
      final fragment = uri.hasFragment ? Uri.decodeComponent(uri.fragment.split(" -> ")[0]) : null;
      name ??= switch (uri.scheme) {
        'ss' => fragment ?? ProxyType.shadowsocks.label,
        'ssconf' => fragment ?? ProxyType.shadowsocks.label,
        'vmess' => ProxyType.vmess.label,
        'vless' => fragment ?? ProxyType.vless.label,
        'trojan' => fragment ?? ProxyType.trojan.label,
        'tuic' => fragment ?? ProxyType.tuic.label,
        'hy2' || 'hysteria2' => fragment ?? ProxyType.hysteria2.label,
        'hy' || 'hysteria' => fragment ?? ProxyType.hysteria.label,
        'ssh' => fragment ?? ProxyType.ssh.label,
        'wg' => fragment ?? ProxyType.wireguard.label,
        'awg' => fragment ?? ProxyType.awg.label,
        'shadowtls' => fragment ?? ProxyType.shadowtls.label,
        'mieru' => fragment ?? ProxyType.mieru.label,
        'warp' => fragment ?? ProxyType.warp.label,
        _ => null,
      };
    }
    return name ?? ProxyType.unknown.label;
  }

  static Map<String, dynamic> applyProfileOverride(Map<String, dynamic> main, String? profileOverride) {
    if (profileOverride == null) return main;
    if (profileOverride.contains("{")) {
      final profileOverrideMap = jsonDecode(profileOverride) as Map<String, dynamic>;
      return _mergeJson(main, profileOverrideMap);
    } else {
      return main;
    }
  }

  static Map<String, dynamic> _mergeJson(Map<String, dynamic> main, Map<String, dynamic> override) {
    override.forEach((key, value) {
      if (main.containsKey(key)) {
        if (main[key] is Map<String, dynamic> && value is Map<String, dynamic>) {
          main[key] = _mergeJson(main[key] as Map<String, dynamic>, value);
        } else {
          main[key] = value;
        }
      } else {
        main[key] = value;
      }
    });
    return main;
  }
}
