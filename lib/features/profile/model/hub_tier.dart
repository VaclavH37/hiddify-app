import 'package:hiddify/features/profile/model/profile_entity.dart';

/// Which hub the outbounds in the current profile dial.
///
/// The middleware decides this from the rolling traffic allowance and emits
/// ONLY the entitled tier's outbounds, so the value is descriptive: the client
/// applies what it is given, explains it, and never picks. It arrives as the
/// `subscription-hub-tier` response header on the subscription fetch and is
/// persisted in `populatedHeaders` — there is no other source for it.
///
/// Both tiers carry the same exit locations under the same tags, so the tier is
/// a property of the *link*, not of the location: it belongs on the quota card
/// and the account section, never in the location picker.
enum HubTier {
  /// The metered, low-latency link. The default in every ambiguous case.
  primary,

  /// The unmetered standby link, used once the rolling allowance is spent.
  standby,
}

/// Request header asking the middleware for a specific tier's outbounds.
///
/// The mirror of the `subscription-hub-tier` RESPONSE header, and deliberately
/// a different name: the response header is the middleware stating what it
/// decided, this one is the client asking to read a different projection. It
/// never influences the tier decision — a subscriber asking for `standby` is
/// precaching a failover config, not opting out of their allowance.
const hubTierRequestHeader = 'x-rayn-hub-tier';

/// Reads [HubTier] from the raw `subscription-hub-tier` header.
///
/// Anything that is not exactly `standby` — absent, blank, a value from a
/// future middleware, garbage — is [HubTier.primary]. Defaulting the *other*
/// way would let a dropped header silently move a paying user onto the standby
/// link, so the safe default is the one that costs us bandwidth rather than the
/// one that costs them speed.
HubTier hubTierOf(String? raw) => raw?.trim().toLowerCase() == 'standby' ? HubTier.standby : HubTier.primary;

/// `subscription-hub-tier-until` had a reader here — `hubTierUntil`, plus a
/// `hubTierCountdown` that turned it into "full speed in 4h" for the quota
/// card. Both went with that card: telling a subscriber when full speed
/// returns tells them it was taken away. The header is still captured into
/// `populatedHeaders` for support, and nothing reads it.
///
/// Reads one persisted subscription response header, or null when it is absent
/// or blank.
///
/// The middleware's subscription metadata reaches the client only through these
/// headers (ProfileParser.allowedProfileHeaders), and they are persisted on
/// the profile row rather than fetched, so this is available on every auth path
/// — including token-import users, who have no account-API session at all.
String? subscriptionHeader(ProfileEntity? profile, String key) {
  final value = profile?.populatedHeaders?[key]?.toString().trim();
  return (value == null || value.isEmpty) ? null : value;
}


/// Minimum time before returning to the PRIMARY hub after a tier reconnect.
///
/// Asymmetric, and that is the whole point — see [shouldReconnectForTier]. A
/// tier change restarts the core, and `select` is built with
/// `interrupt_exist_connections: true`, so every live connection drops; this
/// bounds how often that can happen in the direction where delay is free.
///
/// The middleware owns the real hysteresis: a 1% band plus a 24 h minimum
/// standby dwell, both applied to the return direction only. Since its floor is
/// four times this one, this never binds in normal operation. It earns its keep
/// in one case: on failover to the backup middleware, which runs in a separate
/// Cloudflare account and therefore has no memory of anyone's tier, a subscriber
/// mid-hold is returned to primary early. This suppresses that for the first six
/// hours of a standby leg.
const hubTierDwell = Duration(hours: 6);

/// Whether an observed hub-tier change should be applied to the running core
/// now.
///
/// [applied] is the tier the core is currently running, not the previously
/// observed one — a change that was deferred by the dwell floor leaves the core
/// where it was, and comparing against the last *observation* would then treat
/// the subsequent flip back as a fresh change and reconnect to the tier already
/// in use.
///
/// **Moving TO standby is never delayed.** The floor applies only to the return.
/// The two directions are not symmetric in cost: holding someone on the
/// unmetered standby hub costs nothing, while holding them on the metered
/// CN2-GIA hub spends the budget this whole feature exists to protect. The
/// middleware makes the same split deliberately — its 24 h dwell is return-only
/// — and a symmetric floor here would undo it precisely for the heaviest
/// subscribers, who are the ones it is meant to move.
///
/// The numbers, from the middleware's own measurements: a subscriber burning at
/// 2.6× the accrual rate has a 4.4 h primary leg. That is SHORTER than this
/// floor, so a symmetric version would bind on every cycle, stretching the leg
/// to 6–7 h once the hourly poll is included and lifting their share of time on
/// the metered link from ~15% to ~21%. Higher burn rates make it worse.
///
/// A null [lastSwitchAt] means we have never switched, so nothing is owed.
bool shouldReconnectForTier(HubTier applied, HubTier incoming, DateTime? lastSwitchAt, DateTime now) {
  if (applied == incoming) return false;
  if (incoming == HubTier.standby) return true;
  if (lastSwitchAt == null) return true;
  return now.difference(lastSwitchAt) >= hubTierDwell;
}
