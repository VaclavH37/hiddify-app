/// Which stored config the core is started with.
///
/// A profile can have two sealed blobs: the one the middleware last served, and
/// a precached config for the standby hub. Selecting between them IS the local
/// failover mechanism — there is no other moving part to it.
///
/// This is not the same axis as HubTier, and conflating the two is the mistake
/// worth guarding against. The middleware decides the quota tier and seals
/// whichever outbounds it chose into the *primary* blob, so a subscriber over
/// their allowance runs standby-hub outbounds out of [ConfigSlot.primary]. This
/// enum means only "the client has locally forced the other config", which
/// happens for one reason: the primary hub stopped carrying traffic.
enum ConfigSlot {
  /// `configs/<id>.enc` — whatever the middleware last served.
  primary,

  /// `configs/<id>.standby.enc` — the precached standby-hub config.
  standby,
}

/// The storage identity of a slot: the base name of its file, and the GCM
/// additional authenticated data its blob is sealed under.
///
/// **One function, because three implementations depend on those two agreeing.**
/// The Dart cipher takes the AAD as an argument, but the native readers derive
/// it from the file name — `ConfigCipher.profileIdFor(path)` in
/// `ConfigCipher.kt` and `ConfigCipher.profileId(for:)` in `ConfigCipher.swift`
/// both strip `.enc` off the base name and authenticate with what is left. The
/// qualified name is therefore not a local convention; it is the contract the
/// native side already implements. Qualifying the file without qualifying the
/// AAD would produce a blob only Dart could open, and it would fail exactly
/// where it is hardest to observe: a start the system initiated on its own.
///
/// The qualification also makes slot confusion loud rather than silent. A
/// primary blob copied into the standby slot fails its tag check and surfaces
/// as `ConfigCipherRejection.authFailed`, instead of opening cleanly and
/// running the hub we were trying to get away from.
String configSlotStorageId(String profileId, ConfigSlot slot) => switch (slot) {
  ConfigSlot.primary => profileId,
  ConfigSlot.standby => '$profileId.standby',
};

/// Where the active slot is persisted.
///
/// Absent means [ConfigSlot.primary]. It is persisted rather than held in
/// memory for the same reason the applied hub tier is: on Android the
/// background core outlives the UI, so after a relaunch this is the only record
/// of which config is actually running.
const activeConfigSlotKey = 'active_config_slot';

/// How stale a precached standby config may get before it is refetched.
///
/// The binding constraint is the middleware's Reality shortID rotation, which
/// runs on a 1–2 week cycle. At this cadence a cache is stale only between a
/// rotation and the next daily fetch — uniformly 0–24 h, so about 3.6% of a
/// 14-day cycle, and only harmful if a block lands inside that window.
///
/// Refreshing faster buys very little: the exposure is already the product of
/// two small probabilities, and the real fix is server-side — keeping the
/// previous shortID valid for a couple of days after rotating closes the window
/// entirely, for any cadence.
const standbyCacheMaxAge = Duration(hours: 24);

/// Minimum spacing between standby fetch ATTEMPTS, successful or not.
///
/// Without it a persistently failing fetch — an old middleware that does not
/// honour the tier request, a subscription in a state that cannot serve one —
/// would retry on every refresh cycle, and a user tapping refresh repeatedly
/// would multiply that. One request an hour bounds the cost of a fetch that can
/// never succeed, while still recovering a missing cache far sooner than the
/// 24 h freshness rule alone would.
const standbyRetryFloor = Duration(hours: 1);

/// When the current standby blob was fetched. Absent means there is no cache.
const standbyCachedAtKey = 'standby_cached_at';

/// When a standby fetch was last ATTEMPTED, recorded whether or not it worked.
/// Separate from [standbyCachedAtKey] so a failure backs off without also
/// looking like a successful cache.
const standbyAttemptedAtKey = 'standby_attempted_at';

/// Whether to fetch the standby config now.
///
/// Three rules, in order: back off if we tried too recently; fetch if there is
/// no cache at all; otherwise fetch once the cache passes [standbyCacheMaxAge].
///
/// A timestamp in the FUTURE counts as due rather than as infinitely fresh. The
/// device clock is user-settable and moves backwards across timezone edits and
/// NTP corrections, and the failure modes are not symmetric: treating a future
/// stamp as fresh would freeze the cache permanently, with no way back other
/// than reinstalling.
bool standbyRefreshDue(DateTime? cachedAt, DateTime? attemptedAt, DateTime now) {
  if (attemptedAt != null) {
    final sinceAttempt = now.difference(attemptedAt);
    if (!sinceAttempt.isNegative && sinceAttempt < standbyRetryFloor) return false;
  }
  if (cachedAt == null) return true;
  final age = now.difference(cachedAt);
  return age.isNegative || age >= standbyCacheMaxAge;
}

/// Reads [ConfigSlot] from the persisted value.
///
/// Anything that is not exactly `standby` — absent, blank, garbage, a value
/// written by a future build — is [ConfigSlot.primary]. Defaulting the other
/// way would let one unreadable preference strand a healthy subscriber on the
/// inferior link with nothing in the UI to reveal it, so the safe default is
/// the one that costs us bandwidth rather than the one that costs them speed.
/// Same convention, for the same reason, as `hubTierOf`.
ConfigSlot configSlotOf(String? raw) =>
    raw?.trim().toLowerCase() == 'standby' ? ConfigSlot.standby : ConfigSlot.primary;
