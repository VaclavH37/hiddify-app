// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/utils/rayn_token.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';

late AsymmetricKeyPair _testKey;

String _encrypt(String url, RSAPublicKey publicKey) {
  final cipher = OAEPEncoding.withSHA256(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  final ciphertext = cipher.process(Uint8List.fromList(utf8.encode(url)));
  return base64Url.encode(ciphertext).replaceAll('=', '');
}

String _raynLink(String url) {
  final token = _encrypt(url, _testKey.publicKey as RSAPublicKey);
  return 'rayn://import/$token';
}

void main() {
  setUpAll(() {
    _testKey = CryptoUtils.generateRSAKeyPair(keySize: 4096);
  });

  setUp(() {
    RaynTokenDecryptor.debugSetKey(_testKey.privateKey as RSAPrivateKey);
  });

  group('extractFallback', () {
    test('returns null when `fallback-url` header is absent', () {
      expect(ProfileParser.extractFallback(const {}), isNull);
      expect(
        ProfileParser.extractFallback(const {'content-type': 'application/json'}),
        isNull,
      );
    });

    test('returns null on empty / whitespace header', () {
      expect(ProfileParser.extractFallback(const {'fallback-url': ''}), isNull);
      expect(ProfileParser.extractFallback(const {'fallback-url': '   '}), isNull);
    });

    test('returns null when value is non-rayn https URL', () {
      expect(
        ProfileParser.extractFallback(const {'fallback-url': 'https://malicious.example.com/sub'}),
        isNull,
      );
    });

    test('returns null on rayn:// without /import/ prefix', () {
      expect(
        ProfileParser.extractFallback(const {'fallback-url': 'rayn://something/abc'}),
        isNull,
      );
    });

    test('returns null on rayn://import/ with empty token', () {
      expect(ProfileParser.extractFallback(const {'fallback-url': 'rayn://import/'}), isNull);
    });

    test('returns null when the rayn://import/<token> ciphertext is garbage', () {
      expect(
        ProfileParser.extractFallback(const {'fallback-url': 'rayn://import/not_a_real_token_x'}),
        isNull,
      );
    });

    test('returns decrypted url and full rayn:// link when header is valid', () {
      const url = 'https://api.example.com/sub/abc?x=1';
      final link = _raynLink(url);

      final result = ProfileParser.extractFallback({'fallback-url': link});

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.name, link);
    });

    test('trims surrounding whitespace before parsing', () {
      const url = 'https://api.example.com/sub';
      final link = _raynLink(url);

      final result = ProfileParser.extractFallback({'fallback-url': '  $link  '});

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.name, link);
    });

    test('takes first element when header is a multi-value list', () {
      const url = 'https://api.example.com/sub';
      final link = _raynLink(url);

      final result = ProfileParser.extractFallback({
        'fallback-url': [link, 'rayn://import/ignored_second_value'],
      });

      expect(result, isNotNull);
      expect(result!.url, url);
      expect(result.name, link);
    });

    test('returns null when multi-value list is empty', () {
      expect(ProfileParser.extractFallback({'fallback-url': const <String>[]}), isNull);
    });

    test('returns null when value is an unsupported type', () {
      expect(ProfileParser.extractFallback(const {'fallback-url': 42}), isNull);
      expect(ProfileParser.extractFallback(const {'fallback-url': null}), isNull);
    });

    test('rejects fallback when the underlying decrypt fails (different key)', () {
      final otherKey = CryptoUtils.generateRSAKeyPair(keySize: 4096);
      final token = _encrypt('https://api.example.com/sub', otherKey.publicKey as RSAPublicKey);
      expect(
        ProfileParser.extractFallback({'fallback-url': 'rayn://import/$token'}),
        isNull,
      );
    });
  });

  group('updateRemote failover', () {
    late Directory tempDir;
    late ProviderContainer container;
    late Ref ref;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('fallback_test_');
      container = ProviderContainer();
      ref = container.read(_dummyRefProvider);
    });

    tearDown(() {
      container.dispose();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    RemoteProfileEntity buildEntity({
      String url = 'https://primary.example.com/sub',
      String? fallbackUrl,
      String? fallbackSourceToken,
    }) => RemoteProfileEntity(
      id: 'test-id',
      active: true,
      name: 'test',
      url: url,
      lastUpdate: DateTime(2020),
      fallbackUrl: fallbackUrl,
      fallbackSourceToken: fallbackSourceToken,
    );

    test('primary succeeds → fallback never attempted', () async {
      final fake = _FakeHttpClient(steps: [_FakeStep.ok(headers: {})]);
      final parser = ProfileParser(ref: ref, httpClient: fake);
      final tempPath = '${tempDir.path}/profile';

      final result = await parser
          .updateRemote(rp: buildEntity(fallbackUrl: 'https://fallback.example.com/sub'), tempFilePath: tempPath)
          .run();

      expect(result.isRight(), isTrue);
      expect(fake.callCount, 1);
      expect(fake.calledUrls, ['https://primary.example.com/sub']);
    });

    test('primary fails → fallback succeeds', () async {
      final fake = _FakeHttpClient(steps: [_FakeStep.networkError(), _FakeStep.ok(headers: {})]);
      final parser = ProfileParser(ref: ref, httpClient: fake);
      final tempPath = '${tempDir.path}/profile';

      final result = await parser
          .updateRemote(rp: buildEntity(fallbackUrl: 'https://fallback.example.com/sub'), tempFilePath: tempPath)
          .run();

      expect(result.isRight(), isTrue);
      expect(fake.callCount, 2);
      expect(fake.calledUrls, ['https://primary.example.com/sub', 'https://fallback.example.com/sub']);
    });

    test('primary fails → fallback fails → original primary failure surfaces', () async {
      final fake = _FakeHttpClient(steps: [_FakeStep.networkError(), _FakeStep.networkError()]);
      final parser = ProfileParser(ref: ref, httpClient: fake);
      final tempPath = '${tempDir.path}/profile';

      final result = await parser
          .updateRemote(rp: buildEntity(fallbackUrl: 'https://fallback.example.com/sub'), tempFilePath: tempPath)
          .run();

      expect(result.isLeft(), isTrue);
      expect(fake.callCount, 2);
      // Original primary failure surfaces — not the fallback's. Both are
      // ProfileUnexpectedFailure here, so we just confirm the type.
      result.fold(
        (l) => expect(l, isA<ProfileFailure>()),
        (_) => fail('expected Left'),
      );
    });

    test('primary fails → no fallback configured → primary failure surfaces', () async {
      final fake = _FakeHttpClient(steps: [_FakeStep.networkError()]);
      final parser = ProfileParser(ref: ref, httpClient: fake);
      final tempPath = '${tempDir.path}/profile';

      final result = await parser.updateRemote(rp: buildEntity(), tempFilePath: tempPath).run();

      expect(result.isLeft(), isTrue);
      expect(fake.callCount, 1);
    });

    test('cancellation during primary → fallback never attempted', () async {
      final fake = _FakeHttpClient(steps: [_FakeStep.cancelled()]);
      final parser = ProfileParser(ref: ref, httpClient: fake);
      final tempPath = '${tempDir.path}/profile';

      final result = await parser
          .updateRemote(rp: buildEntity(fallbackUrl: 'https://fallback.example.com/sub'), tempFilePath: tempPath)
          .run();

      expect(result.isLeft(), isTrue);
      expect(fake.callCount, 1);
      result.fold(
        (l) => expect(l, isA<ProfileCancelByUserFailure>()),
        (_) => fail('expected Left'),
      );
    });

    test('header absence preserves existing fallback', () async {
      const existingFallback = 'https://old-fallback.example.com/sub';
      final existingToken = _raynLink(existingFallback);
      final fake = _FakeHttpClient(steps: [_FakeStep.ok(headers: {})]);
      final parser = ProfileParser(ref: ref, httpClient: fake);
      final tempPath = '${tempDir.path}/profile';

      final result = await parser
          .updateRemote(
            rp: buildEntity(fallbackUrl: existingFallback, fallbackSourceToken: existingToken),
            tempFilePath: tempPath,
          )
          .run();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('expected Right'),
        (companion) {
          expect(companion.fallbackUrl.value, existingFallback);
          expect(companion.fallbackSourceToken.value, existingToken);
        },
      );
    });

    test('present fallback-url header populates the columns', () async {
      const newFallback = 'https://new-fallback.example.com/sub';
      final newLink = _raynLink(newFallback);
      final fake = _FakeHttpClient(steps: [_FakeStep.ok(headers: {'fallback-url': newLink})]);
      final parser = ProfileParser(ref: ref, httpClient: fake);
      final tempPath = '${tempDir.path}/profile';

      final result = await parser.updateRemote(rp: buildEntity(), tempFilePath: tempPath).run();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('expected Right'),
        (companion) {
          expect(companion.fallbackUrl.value, newFallback);
          expect(companion.fallbackSourceToken.value, newLink);
        },
      );
    });
  });
}

final _dummyRefProvider = Provider<Ref>((ref) => ref);

class _FakeStep {
  _FakeStep._({this.headers, this.error});
  factory _FakeStep.ok({required Map<String, dynamic> headers}) => _FakeStep._(headers: headers);
  factory _FakeStep.networkError() => _FakeStep._(error: _NetworkErrorMarker());
  factory _FakeStep.cancelled() => _FakeStep._(error: _CancelMarker());

  final Map<String, dynamic>? headers;
  final Object? error;
}

class _NetworkErrorMarker {}

class _CancelMarker {}

class _FakeHttpClient extends DioHttpClient {
  _FakeHttpClient({required this.steps})
    : super(timeout: const Duration(seconds: 1), userAgent: 'test', debug: false);

  final List<_FakeStep> steps;
  int callCount = 0;
  final List<String> calledUrls = [];

  @override
  Future<Response> download(
    String url,
    String path, {
    CancelToken? cancelToken,
    String? userAgent,
    ({String username, String password})? credentials,
    bool proxyOnly = false,
  }) async {
    final idx = callCount;
    callCount++;
    calledUrls.add(url);
    if (idx >= steps.length) {
      throw StateError('unexpected extra download call: $url');
    }
    final step = steps[idx];
    if (step.error != null) {
      if (step.error is _CancelMarker) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: url),
          reason: 'cancelled',
        );
      }
      throw DioException(
        requestOptions: RequestOptions(path: url),
        type: DioExceptionType.connectionError,
        message: 'fake network error',
      );
    }
    // Write empty body so expandRemoteLinesInParallel has nothing to fetch.
    await File(path).writeAsString('');
    final headersMap = <String, List<String>>{};
    step.headers!.forEach((k, v) {
      if (v is List) {
        headersMap[k] = v.map((e) => e.toString()).toList();
      } else {
        headersMap[k] = [v.toString()];
      }
    });
    return Response(
      requestOptions: RequestOptions(path: url),
      headers: Headers.fromMap(headersMap),
      statusCode: 200,
    );
  }

  @override
  Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(seconds: 5)}) async => false;
}
