import 'package:hiddify/core/app_update/update_manifest.dart';

/// How often a connected Windows client asks for a newer release.
const appUpdateCheckInterval = Duration(hours: 12);

/// When to ask again after the manifest could not be fetched.
const appUpdateRetryAfterFailure = Duration(hours: 1);

/// A release put off with "Later" is offered again after this long.
const appUpdateRepromptAfter = Duration(hours: 24);

sealed class UpdateDecision {
  const UpdateDecision();
}

/// The running build is the published one, or newer.
class UpdateNotNewer extends UpdateDecision {
  const UpdateNotNewer();
}

/// Signed by us, but not for this client. Worth a log line.
class UpdateRefused extends UpdateDecision {
  const UpdateRefused(this.why);
  final String why;
}

class UpdateOffer extends UpdateDecision {
  const UpdateOffer(this.manifest);
  final UpdateManifest manifest;
}

/// What to make of a manifest whose signature has already verified.
///
/// [seenPublishedAt] is the newest `published_at` this client has accepted: a
/// manifest older than that is a stale copy served again, which could only be
/// hiding a newer release. The signature covers both `build` and
/// `published_at`, so neither can be edited to get past this.
UpdateDecision updateDecision(
  UpdateManifest manifest, {
  required String channel,
  required int currentBuild,
  DateTime? seenPublishedAt,
}) {
  if (manifest.platform != 'windows') return UpdateRefused('platform ${manifest.platform}');
  if (manifest.channel != channel) return UpdateRefused('channel ${manifest.channel}, this build reads $channel');
  if (seenPublishedAt != null && manifest.publishedAt.isBefore(seenPublishedAt)) {
    return const UpdateRefused('older than a manifest already seen');
  }
  if (manifest.build <= currentBuild) return const UpdateNotNewer();
  return UpdateOffer(manifest);
}

/// Whether to put the update dialog in front of the user now.
///
/// - An important release asks once per app run (per build), whatever was
///   chosen before, and cannot be skipped.
/// - Any other release asks when it first appears, then at most once every
///   [appUpdateRepromptAfter] after "Later", and never again after "Skip this
///   version".
///
/// [promptedBuildThisRun] is held in memory, so it starts empty at each launch.
bool shouldPromptForUpdate(
  UpdateManifest offer, {
  required DateTime now,
  int? promptedBuildThisRun,
  int? skippedBuild,
  int? promptedBuild,
  DateTime? promptedAt,
}) {
  if (offer.important) return promptedBuildThisRun != offer.build;
  if (skippedBuild == offer.build) return false;
  if (promptedBuild != offer.build || promptedAt == null) return true;
  final since = now.difference(promptedAt);
  return since.isNegative || since >= appUpdateRepromptAfter;
}
