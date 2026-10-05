import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/app_update/update_decision.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:hiddify/core/app_update/update_signing.dart';
import 'package:hiddify/core/app_update/update_store.dart';
import 'package:pointycastle/export.dart' show ECPrivateKey;
import 'package:shared_preferences/shared_preferences.dart';

/// One check against the update host: fetch, verify against the pinned keys,
/// decide, remember. Signatures here are real, made with a throwaway key.
void main() {
  final pair = generateUpdateKeyPair(Random(1));
  final other = generateUpdateKeyPair(Random(2));
  final pinned = {'k1': encodeUpdatePublicKey(pair.publicKey)};
  final now = DateTime.utc(2026, 10, 21, 12);
  const url = 'https://cdn.raynlabs.io/app/windows/stable/MANIFEST';

  String envelope({
    int build = 10602,
    String channel = 'stable',
    DateTime? publishedAt,
    bool important = false,
    ECPrivateKey? key,
  }) {
    final manifest = UpdateManifest(
      schema: kUpdateManifestSchema,
      platform: 'windows',
      channel: channel,
      version: '1.6.${build - 10600}',
      build: build,
      publishedAt: publishedAt ?? DateTime.utc(2026, 10, 20, 9),
      important: important,
      installer: UpdateInstaller(
        path: 'app/windows/RaynVPN-1.6.${build - 10600}-$build-windows.exe',
        size: 32883242,
        sha256: 'a' * 64,
      ),
    );
    return signUpdateEnvelope(payload: encodeUpdatePayload(manifest), keyId: 'k1', key: key ?? pair.privateKey);
  }

  late AppUpdateStore store;
  late List<(String, int)> fetches;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AppUpdateStore(await SharedPreferences.getInstance());
    fetches = [];
  });

  AppUpdateCheck check({Object? serve, int currentBuild = 10601}) => AppUpdateCheck(
    store: store,
    manifestUrl: url,
    channel: 'stable',
    currentBuild: currentBuild,
    pinnedKeys: pinned,
    clock: () => now,
    fetch: (u, maxBytes) async {
      fetches.add((u, maxBytes));
      return switch (serve) {
        final String body => Uint8List.fromList(utf8.encode(body)),
        final Uint8List bytes => bytes,
        final Exception e => throw e,
        _ => throw StateError('nothing to serve'),
      };
    },
  );

  test('a newer signed release is offered and remembered as the envelope it came in', () async {
    final body = envelope();
    final result = await check(serve: body).run();

    expect(result.outcome, AppUpdateOutcome.offered);
    expect(result.offer?.build, 10602);
    expect(result.next, appUpdateCheckInterval);
    expect(fetches, [(url, kUpdateMaxManifestBytes)]);
    expect(store.lastCheck, now);
    expect(store.seenPublishedAt, DateTime.utc(2026, 10, 20, 9));
    final restored = await store.loadOffer(pinnedKeys: pinned, channel: 'stable', currentBuild: 10601);
    expect(restored?.build, 10602);
  });

  test('nothing is fetched within the interval unless the user asks', () async {
    await check(serve: envelope()).run();
    fetches.clear();

    final scheduled = await check(serve: envelope()).run();
    expect(scheduled.outcome, AppUpdateOutcome.notDue);
    expect(scheduled.offer?.build, 10602, reason: 'the stored offer still shows');
    expect(scheduled.next, appUpdateCheckInterval);
    expect(fetches, isEmpty);

    final asked = await check(serve: envelope()).run(force: true);
    expect(asked.outcome, AppUpdateOutcome.offered);
    expect(fetches, hasLength(1));
  });

  test('an unreachable host is retried within the hour and leaves the last check alone', () async {
    await store.saveOffer(envelope());
    final result = await check(
      serve: DioException(requestOptions: RequestOptions(path: url)),
    ).run();

    expect(result.outcome, AppUpdateOutcome.failed);
    expect(result.next, appUpdateRetryAfterFailure);
    expect(result.offer?.build, 10602, reason: 'a failed check does not forget the offer');
    expect(store.lastCheck, isNull);
  });

  test('a manifest that does not verify is refused, and the stored offer stays', () async {
    await store.saveOffer(envelope());
    for (final bad in [
      envelope(build: 10603, key: other.privateKey),
      'not json',
      Uint8List.fromList([0xff, 0xfe, 0x00]),
    ]) {
      final result = await check(serve: bad).run(force: true);
      expect(result.outcome, AppUpdateOutcome.refused, reason: '$bad');
      expect(result.offer?.build, 10602);
      expect(result.next, appUpdateCheckInterval);
    }
    expect(store.lastCheck, now, reason: 'a definite answer counts as a check');
  });

  test('the build now running is up to date, and a stored offer for it goes', () async {
    await store.saveOffer(envelope());
    final result = await check(serve: envelope(), currentBuild: 10602).run();

    expect(result.outcome, AppUpdateOutcome.upToDate);
    expect(result.offer, isNull);
    expect(await store.loadOffer(pinnedKeys: pinned, channel: 'stable', currentBuild: 10601), isNull);
  });

  test('an older manifest served again cannot replace a newer one already seen', () async {
    await check(serve: envelope(build: 10603, publishedAt: DateTime.utc(2026, 10, 25))).run();
    final replay = await check(serve: envelope(publishedAt: DateTime.utc(2026, 10, 20))).run(force: true);

    expect(replay.outcome, AppUpdateOutcome.refused);
    expect(replay.offer?.build, 10603);
  });

  test("another channel's manifest is refused", () async {
    final result = await check(serve: envelope(channel: 'test')).run();
    expect(result.outcome, AppUpdateOutcome.refused);
    expect(result.offer, isNull);
  });

  group('AppUpdateStore', () {
    test('a stored offer is verified again on every read; an edited one is dropped', () async {
      final json = jsonDecode(envelope()) as Map<String, dynamic>;
      final payload = jsonDecode(utf8.decode(base64.decode(json['payload'] as String))) as Map<String, dynamic>;
      payload['installer'] = {...payload['installer'] as Map<String, dynamic>, 'sha256': 'b' * 64};
      json['payload'] = base64.encode(utf8.encode(jsonEncode(payload)));
      await store.saveOffer(jsonEncode(json));

      expect(await store.loadOffer(pinnedKeys: pinned, channel: 'stable', currentBuild: 10601), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppUpdateStore.offerKey), isNull);
    });

    test('an offer for the build now running is dropped: it was installed', () async {
      await store.saveOffer(envelope());
      expect(await store.loadOffer(pinnedKeys: pinned, channel: 'stable', currentBuild: 10602), isNull);
    });

    test('the newest published_at is kept', () async {
      await store.recordSeen(DateTime.utc(2026, 10, 25));
      await store.recordSeen(DateTime.utc(2026, 10, 20));
      expect(store.seenPublishedAt, DateTime.utc(2026, 10, 25));
    });

    test('the install attempt is remembered until the next launch settles it', () async {
      expect(store.attemptBuild, isNull);
      await store.recordAttempt(10602);
      expect(store.attemptBuild, 10602);
      await store.clearAttempt();
      expect(store.attemptBuild, isNull);
    });

    test('skip and prompt are remembered', () async {
      await store.skip(10602);
      await store.recordPrompt(10603, now);
      expect(store.skippedBuild, 10602);
      expect(store.promptedBuild, 10603);
      expect(store.promptedAt, now);
    });
  });
}
