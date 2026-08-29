import 'dart:convert';

import 'package:dartx/dartx.dart';
import 'package:dio/dio.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/features/profile/model/hub_tier.dart';
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

/// The terminal response of a subscription request: the headers, the `url` and
/// `sourceToken` that produced it (the renewed pair when a `new-url` rotation
/// was followed), and the body.
typedef _ResolvedSubscription = ({Map<String, dynamic> headers, String url, String? sourceToken, String content});

/// A parsed profile plus the subscription body it came from.
///
/// The body is carried in memory, never through a file: it holds the hub IP,
/// the per-user UUIDs and the Reality shortIDs, and the caller seals it into
/// `configs/<id>.enc` immediately. Writing it to a temp file first — as this
/// parser used to — left plaintext on disk for the length of the request, and
/// permanently if the process was killed before the cleanup `finally` ran.
typedef ParsedProfile = ({ProfileEntriesCompanion entry, String content});

class ProfileParser {
  // Synthetic sentinel assigned to `total` for "unlimited" traffic
  // (subscription-userinfo total=0 or missing); see [_parseSubInfo], which stores
  // `infiniteTrafficThreshold + 1`.
  //
  // It doubles as the *test* for unlimited, and that is what makes its magnitude
  // load-bearing: notification_evaluator.dart gates the 80/90/100% quota alerts on
  // `subInfo.total > infiniteTrafficThreshold`. The previous value (~857 GiB) was
  // small enough that any ordinary plan above it was classified unlimited, so those
  // users received no quota notifications at all. 1000 TiB is above any real plan.
  //
  // Upstream raised it for a different reason — its `isInfinitSize()` gate renders
  // "∞" above 10 TB, and the old sentinel fell below that, so unlimited plans showed
  // a finite cap (hiddify/hiddify-app#1974). That half does not apply here:
  // isInfinitSize() has no callers in this fork and profile_tile.dart is deleted.
  // Kept aligned with upstream anyway, since both failures share this one constant.
  static const infiniteTrafficThreshold = 1_099_511_627_776_000;
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
    // Which hub the emitted outbounds dial. The middleware decides it from the
    // rolling traffic allowance and emits ONLY that tier's outbounds, so this
    // header is descriptive — the client never picks. Absent means primary; see
    // HubTier.
    'subscription-hub-tier',
    'subscription-hub-tier-until',
  ];

  final Ref _ref;
  final DioHttpClient _httpClient;

  static final _log = Loggy('profile_parser');

  ProfileParser({required Ref ref, required DioHttpClient httpClient}) : _ref = ref, _httpClient = httpClient;
  TaskEither<ProfileFailure, ParsedProfile> addLocal({
    required String id,
    required String content,
    required UserOverride? userOverride,
  }) {
    return TaskEither.tryCatch(
          () => expandRemoteLines(content: content, httpClient: _httpClient, cancelToken: CancelToken(), ref: _ref),
          (_, _) => const ProfileFailure.unexpected(),
        )
        .flatMap(
          (expanded) => TaskEither.fromEither(
            populateHeaders(content: expanded).map((h) => (headers: h, content: expanded)),
          ),
        )
        .flatMap(
          (resolved) => TaskEither.fromEither(
            parse(
              content: resolved.content,
              profile: ProfileEntity.local(
                id: id,
                active: true,
                name: '',
                lastUpdate: DateTime.now(),
                userOverride: userOverride,
                populatedHeaders: resolved.headers,
              ),
            )
                .flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected))
                .map((entry) => (entry: entry, content: resolved.content)),
          ),
        );
  }

  TaskEither<ProfileFailure, ParsedProfile> addRemote({
    required String id,
    required String url,
    required UserOverride? userOverride,
    String? sourceToken,
    CancelToken? cancelToken,
  }) => _resolveDownload(url, sourceToken, cancelToken).flatMap((resolved) {
    final fallback = extractFallback(resolved.headers);
    if (fallback != null) {
      _log.info('capturing fallback URL on import (host: ${Uri.tryParse(fallback.url)?.host ?? "?"})');
    }
    return TaskEither.fromEither(
      populateHeaders(content: resolved.content, remoteHeaders: resolved.headers),
    ).flatMap(
      (populatedHeaders) => TaskEither.fromEither(
        parse(
          content: resolved.content,
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
        )
            .flatMap((profEntity) => Either.tryCatch(() => profEntity.toInsertEntry(), ProfileFailure.unexpected))
            .map((entry) => (entry: entry, content: resolved.content)),
      ),
    );
  });

  TaskEither<ProfileFailure, ParsedProfile> updateRemote({
    required RemoteProfileEntity rp,
    CancelToken? cancelToken,
    HubSignal? signal,
    HubCounters? counters,
  }) => _downloadWithFailover(rp, cancelToken, signal: signal, counters: counters).flatMap((resolved) {
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
      populateHeaders(content: resolved.content, remoteHeaders: resolved.headers),
    ).flatMap(
      (populatedHeaders) => TaskEither.fromEither(
        parse(
          content: resolved.content,
          profile: rotated.copyWith(populatedHeaders: populatedHeaders),
        )
            .flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected))
            .map((entry) => (entry: entry, content: resolved.content)),
      ),
    );
  });

  Either<ProfileFailure, ParsedProfile> offlineUpdate({
    required ProfileEntity profile,
    required String content,
  }) => profile
      .map(
        remote: (rp) => parse(profile: rp, content: content),
        local: (lp) => parse(content: content, profile: lp),
      )
      .flatMap((profEntity) => Either.tryCatch(() => profEntity.toUpdateEntry(), ProfileFailure.unexpected))
      .map((entry) => (entry: entry, content: content));

  /// [signal], when present, rides along as the `x-rayn-hub-signal` request
  /// header and forces the DIRECT leg.
  ///
  /// Direct is not an optimisation here, it is the point: the only reason to
  /// send `unreachable` is that the tunnel does not carry traffic, so routing
  /// the escalation through it would burn the full timeout before falling back.
  TaskEither<ProfileFailure, ({Map<String, dynamic> headers, String content})> _downloadProfile(
    String url,
    CancelToken? cancelToken, {
    HubSignal? signal,
    HubTier? requestTier,
    HubCounters? counters,
  }) => TaskEither.tryCatch(() async {
    // if (url.startsWith("http://"))
    //   throw const ProfileFailure.invalidUrl('HTTP is not supported. Please use HTTPS for secure connection.');

    // getText, not download: the body must stay in memory (see [ParsedProfile]).
    final rs = await _httpClient
        .getText(
          url.trim(),
          cancelToken: cancelToken,
          userAgent: _ref.read(appInfoProvider).requireValue.subscriptionUserAgent,
          extraHeaders: _requestHeaders(signal: signal, requestTier: requestTier, counters: counters),
        )
        .catchError((err) {
          if (CancelToken.isCancel(err as DioException)) {
            throw const ProfileFailure.cancelByUser('HTTP request for getting profile content canceled by user.');
          }
          throw err;
        });
    final content = await expandRemoteLines(
      content: rs.data ?? '',
      httpClient: _httpClient,
      cancelToken: cancelToken ?? CancelToken(),
      ref: _ref,
    );
    // fixing headers before return
    final headers = rs.headers.map.map((key, value) {
      if (value.length == 1) return MapEntry(key, value.first);
      return MapEntry(key, value);
    });
    return (headers: headers, content: content);
  }, (err, st) => err is ProfileFailure ? err : ProfileFailure.unexpected(err, st));

  /// Builds the optional request headers a subscription fetch may carry.
  ///
  /// Null rather than an empty map when there is nothing to send, so an
  /// ordinary refresh is byte-for-byte the request it has always been — every
  /// header the client adds is one more thing that distinguishes this app's
  /// traffic from anything else's.
  static Map<String, String>? _requestHeaders({
    HubSignal? signal,
    HubTier? requestTier,
    HubCounters? counters,
  }) {
    final headers = <String, String>{
      if (signal != null) hubSignalHeader: signal.wireValue,
      if (requestTier != null) hubTierRequestHeader: requestTier.name,
      // Both or neither, and only with something to say. A window of zero
      // observations is not a measurement, and sending it would put a
      // meaningless denominator into the middleware's aggregation.
      if (counters != null && counters.checks > 0) ...{
        hubChecksHeader: '${counters.checks}',
        hubFailuresHeader: '${counters.failures}',
      },
    };
    return headers.isEmpty ? null : headers;
  }

  /// Fetches the STANDBY-hub config body, and nothing else.
  ///
  /// Deliberately NOT an `updateRemote` variant. It returns only the body: the
  /// response's headers describe the standby projection, and letting them reach
  /// `populatedHeaders` would overwrite the live tier and quota metadata that
  /// the account UI reads. The primary refresh path stays the only writer of
  /// stored profile state.
  ///
  /// A `new-url` this fetch follows is likewise discarded. That is safe because
  /// rotation is idempotent — the old token stays valid and every later
  /// response re-offers the renewal — so the next primary refresh records it.
  ///
  /// The tier guard is the important part. A middleware that does not implement
  /// the request header answers with the PRIMARY config, and sealing that into
  /// the standby slot would be worse than having no cache at all: failover
  /// would swap primary for primary, restart the core, and change nothing,
  /// while looking like it had worked.
  TaskEither<ProfileFailure, String> fetchStandbyConfig({
    required RemoteProfileEntity rp,
    CancelToken? cancelToken,
  }) => _downloadWithFailover(rp, cancelToken, requestTier: HubTier.standby).flatMap((resolved) {
    final served = hubTierOf(resolved.headers['subscription-hub-tier']?.toString());
    if (served != HubTier.standby) {
      _log.warning('standby fetch answered with the [${served.name}] tier; discarding it');
      return TaskEither<ProfileFailure, String>.left(
        const ProfileFailure.invalidConfig('the middleware did not serve the standby hub'),
      );
    }
    return TaskEither<ProfileFailure, String>.right(resolved.content);
  });

  /// One subscription request that follows `new-url` token rotation to the
  /// terminal response (see [Confirmed decisions] in the plan). Returns the
  /// terminal `headers` plus the `url`/`sourceToken` that produced it (the
  /// renewed token when a `new-url` was followed). A terminal `4010` envelope
  /// with no (further) `new-url` is a lapsed subscription →
  /// [ProfileFailure.subscriptionExpired]. Capped at [_maxRotationHops].
  TaskEither<ProfileFailure, _ResolvedSubscription> _resolveDownload(
    String url,
    String? sourceToken,
    CancelToken? cancelToken, {
    int depth = 0,
    HubSignal? signal,
    HubTier? requestTier,
    HubCounters? counters,
  }) => _downloadProfile(
        url,
        cancelToken,
        signal: signal,
        requestTier: requestTier,
        counters: counters,
      ).flatMap((downloaded) {
    final rotation = extractRotation(downloaded.headers);
    // Compare the DECRYPTED url, not the cryptolink: the envelope is randomised,
    // so the same URL re-encrypts to a different string on every response and a
    // string comparison would follow a "rotation" on every single refresh (§4).
    if (rotation != null && rotation.url != url && depth < _maxRotationHops) {
      _log.info(
        'following `new-url` to renewed token (hop ${depth + 1}, host: ${Uri.tryParse(rotation.url)?.host ?? "?"})',
      );
      return _resolveDownload(
        rotation.url,
        rotation.sourceToken,
        cancelToken,
        depth: depth + 1,
        signal: signal,
        requestTier: requestTier,
        counters: counters,
      );
    }
    if (isExpiredEnvelope(downloaded.content)) {
      _log.warning('subscription token expired with no renewal available');
      return TaskEither<ProfileFailure, _ResolvedSubscription>.left(const ProfileFailure.subscriptionExpired());
    }
    return TaskEither.right((
      headers: downloaded.headers,
      url: url,
      sourceToken: sourceToken,
      content: downloaded.content,
    ));
  });

  /// Wraps [_resolveDownload] with the fallback-URL failover policy. Used by
  /// [updateRemote] only — initial imports have no stored fallback yet.
  ///
  /// Failover triggers on any [ProfileFailure] from the primary except
  /// [ProfileCancelByUserFailure] (user intent) and
  /// [ProfileSubscriptionExpiredFailure] (an account state — the fallback host
  /// would return the same `4010`, so we surface the lapse instead).
  TaskEither<ProfileFailure, _ResolvedSubscription> _downloadWithFailover(
    RemoteProfileEntity rp,
    CancelToken? cancelToken, {
    HubSignal? signal,
    HubTier? requestTier,
    HubCounters? counters,
  }) => TaskEither(() async {
    final primary = await _resolveDownload(
      rp.url,
      rp.sourceToken,
      cancelToken,
      signal: signal,
      requestTier: requestTier,
      counters: counters,
    ).run();
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
    final secondary = await _resolveDownload(
      fallback,
      rp.fallbackSourceToken,
      cancelToken,
      signal: signal,
      requestTier: requestTier,
      counters: counters,
    ).run();
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

  /// Expands a line-list subscription: any line that is itself an http(s) URL is
  /// fetched and substituted inline. Returns the expanded body.
  ///
  /// Everything here is in memory. The previous file-based version downloaded
  /// each nested URL to `<temp>.<index>` and never deleted those fragments —
  /// the caller's cleanup only removed the base temp file — so a line-list
  /// subscription left plaintext node data in `configs/` indefinitely.
  Future<String> expandRemoteLines({
    required String content,
    required DioHttpClient httpClient,
    required CancelToken cancelToken,
    required Ref ref,
    int parallelism = 4,
  }) async {
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
          final rs = await httpClient.getText(
            line,
            cancelToken: cancelToken,
            userAgent: ref.read(appInfoProvider).requireValue.subscriptionUserAgent,
          );
          results[currentIndex] = (rs.data ?? '').trim();
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
      return results.join("\n");
    }
    return content;
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
  static Either<ProfileFailure, ProfileEntity> parse({required String content, required ProfileEntity profile}) =>
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
              name = protocol(content);
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
