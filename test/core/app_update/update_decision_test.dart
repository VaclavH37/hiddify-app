import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_update/update_check.dart';
import 'package:hiddify/core/app_update/update_decision.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';

/// Which signed manifests a Windows client offers, and when it asks the user.
/// The signature has already verified by the time these run; they decide what
/// a genuine manifest means for this client.
void main() {
  final published = DateTime.utc(2026, 10, 20, 9);

  UpdateManifest manifest({
    String platform = 'windows',
    String channel = 'stable',
    int build = 10602,
    DateTime? publishedAt,
    bool important = false,
  }) => UpdateManifest(
    schema: kUpdateManifestSchema,
    platform: platform,
    channel: channel,
    version: '1.6.2',
    build: build,
    publishedAt: publishedAt ?? published,
    important: important,
    installer: UpdateInstaller(path: 'app/windows/RaynVPN-1.6.2-$build-windows.exe', size: 32883242, sha256: 'a' * 64),
  );

  group('updateDecision', () {
    UpdateDecision decide(UpdateManifest m, {int currentBuild = 10601, DateTime? seen}) =>
        updateDecision(m, channel: 'stable', currentBuild: currentBuild, seenPublishedAt: seen);

    test('a newer build on this channel is offered', () {
      final m = manifest();
      expect(decide(m), isA<UpdateOffer>().having((d) => d.manifest, 'manifest', same(m)));
    });

    test('the running build, or an older one, is not newer', () {
      expect(decide(manifest(), currentBuild: 10602), isA<UpdateNotNewer>());
      expect(decide(manifest(build: 10500)), isA<UpdateNotNewer>());
    });

    test('another platform or channel is refused, even when newer', () {
      expect(decide(manifest(platform: 'macos')), isA<UpdateRefused>());
      expect(decide(manifest(channel: 'test')), isA<UpdateRefused>());
    });

    test('a manifest older than one already seen is refused: it could only hide a newer release', () {
      final later = published.add(const Duration(days: 3));
      expect(decide(manifest(), seen: later), isA<UpdateRefused>());
      expect(decide(manifest(), seen: published), isA<UpdateOffer>(), reason: 'the same manifest again is fine');
    });
  });

  group('shouldPromptForUpdate', () {
    final now = DateTime.utc(2026, 10, 21, 12);

    test('a release asks when it first appears', () {
      expect(shouldPromptForUpdate(manifest(), now: now), isTrue);
    });

    test('after "Later" it asks again only after a day', () {
      bool ask(Duration ago) =>
          shouldPromptForUpdate(manifest(), now: now, promptedBuild: 10602, promptedAt: now.subtract(ago));
      expect(ask(const Duration(hours: 1)), isFalse);
      expect(ask(const Duration(hours: 23, minutes: 59)), isFalse);
      expect(ask(appUpdateRepromptAfter), isTrue);
      expect(ask(const Duration(hours: -2)), isTrue, reason: 'a prompt time in the future means the clock moved');
    });

    test('a newer release asks at once, whatever was put off before', () {
      expect(
        shouldPromptForUpdate(
          manifest(build: 10603),
          now: now,
          promptedBuild: 10602,
          promptedAt: now.subtract(const Duration(minutes: 5)),
        ),
        isTrue,
      );
    });

    test('a skipped release never asks again; the next one does', () {
      expect(shouldPromptForUpdate(manifest(), now: now, skippedBuild: 10602), isFalse);
      expect(shouldPromptForUpdate(manifest(build: 10603), now: now, skippedBuild: 10602), isTrue);
    });

    test('an important release asks once per run, even if it was skipped or put off', () {
      final important = manifest(important: true);
      expect(
        shouldPromptForUpdate(
          important,
          now: now,
          skippedBuild: 10602,
          promptedBuild: 10602,
          promptedAt: now.subtract(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(shouldPromptForUpdate(important, now: now, promptedBuildThisRun: 10602), isFalse);
      expect(
        shouldPromptForUpdate(manifest(build: 10603, important: true), now: now, promptedBuildThisRun: 10602),
        isTrue,
      );
    });
  });

  test('the installer size reads in whole megabytes, never zero', () {
    expect(appUpdateMegabytes(32883242), 31);
    expect(appUpdateMegabytes(150 * 1024 * 1024), 150);
    expect(appUpdateMegabytes(1000), 1);
  });

  test('the manifest lives under the channel', () {
    expect(
      appUpdateManifestUrl('https://cdn.raynlabs.io', 'stable'),
      'https://cdn.raynlabs.io/app/windows/stable/MANIFEST',
    );
  });
}
