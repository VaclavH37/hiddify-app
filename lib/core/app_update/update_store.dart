import 'package:hiddify/core/app_update/update_decision.dart';
import 'package:hiddify/core/app_update/update_manifest.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Windows updater remembers between runs, in SharedPreferences.
///
/// The pending offer is kept as the signed envelope it arrived in and verified
/// again every time it is read, because the preferences file sits in the
/// user's profile where any process the user runs can write it. Only an
/// administrator can write where the installer is downloaded (U3); nothing
/// read from here is trusted without its signature.
class AppUpdateStore {
  AppUpdateStore(this._prefs);

  final SharedPreferences _prefs;

  static const lastCheckKey = 'app_update_last_check';
  static const offerKey = 'app_update_offer';
  static const seenPublishedAtKey = 'app_update_seen_published_at';
  static const skippedBuildKey = 'app_update_skipped_build';
  static const promptedAtKey = 'app_update_prompted_at';
  static const promptedBuildKey = 'app_update_prompted_build';
  static const attemptBuildKey = 'app_update_attempt_build';

  DateTime? get lastCheck => _time(lastCheckKey);

  Future<void> recordCheck(DateTime at) => _prefs.setInt(lastCheckKey, at.millisecondsSinceEpoch);

  /// The newest `published_at` of any manifest that verified. An older one is
  /// refused from then on, so a stale manifest served again cannot hide a
  /// newer release.
  DateTime? get seenPublishedAt => _time(seenPublishedAtKey);

  Future<void> recordSeen(DateTime publishedAt) async {
    final seen = seenPublishedAt;
    if (seen != null && !publishedAt.isAfter(seen)) return;
    await _prefs.setInt(seenPublishedAtKey, publishedAt.millisecondsSinceEpoch);
  }

  /// The build the user asked not to be prompted about again.
  int? get skippedBuild => _prefs.getInt(skippedBuildKey);

  Future<void> skip(int build) => _prefs.setInt(skippedBuildKey, build);

  DateTime? get promptedAt => _time(promptedAtKey);
  int? get promptedBuild => _prefs.getInt(promptedBuildKey);

  Future<void> recordPrompt(int build, DateTime at) async {
    await _prefs.setInt(promptedBuildKey, build);
    await _prefs.setInt(promptedAtKey, at.millisecondsSinceEpoch);
  }

  /// The build an update was installing when the app last exited for it.
  /// The next launch settles it: the new build says "Updated", the old one
  /// says the install did not finish.
  int? get attemptBuild => _prefs.getInt(attemptBuildKey);

  Future<void> recordAttempt(int build) => _prefs.setInt(attemptBuildKey, build);

  Future<void> clearAttempt() => _prefs.remove(attemptBuildKey);

  Future<void> saveOffer(String envelope) => _prefs.setString(offerKey, envelope);

  Future<void> clearOffer() => _prefs.remove(offerKey);

  /// The stored offer, if its signature still verifies against [pinnedKeys]
  /// and it is still an offer for this build on [channel]. Anything else is
  /// removed: an offer for the build now running was installed, and one that
  /// no longer verifies was never ours.
  Future<UpdateManifest?> loadOffer({
    required Map<String, String> pinnedKeys,
    required String channel,
    required int currentBuild,
  }) async {
    final envelope = _prefs.getString(offerKey);
    if (envelope == null) return null;
    try {
      final manifest = verifyUpdateEnvelope(envelope, pinnedKeys);
      if (updateDecision(manifest, channel: channel, currentBuild: currentBuild) case UpdateOffer()) return manifest;
    } on UpdateManifestException {
      // Fall through and forget it.
    }
    await clearOffer();
    return null;
  }

  DateTime? _time(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
}
