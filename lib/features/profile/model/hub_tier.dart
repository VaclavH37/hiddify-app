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

/// Reads [HubTier] from the raw `subscription-hub-tier` header.
///
/// Anything that is not exactly `standby` — absent, blank, a value from a
/// future middleware, garbage — is [HubTier.primary]. Defaulting the *other*
/// way would let a dropped header silently move a paying user onto the standby
/// link, so the safe default is the one that costs us bandwidth rather than the
/// one that costs them speed.
HubTier hubTierOf(String? raw) => raw?.trim().toLowerCase() == 'standby' ? HubTier.standby : HubTier.primary;

/// Reads `subscription-hub-tier-until` — unix seconds at which the accrued
/// allowance is projected to overtake consumption, i.e. when the primary link
/// comes back.
///
/// Treats 0 / absent / unparseable as *unknown* and returns null, so the UI
/// hides the figure rather than showing a stale or epoch-zero one. Same
/// convention as `subscription-refill-date` in ProfileParser.parse.
DateTime? hubTierUntil(String? raw) {
  final seconds = int.tryParse(raw?.trim() ?? '');
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

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

/// How long until the primary link returns, expressed in whole hours or whole
/// days, or null when there is nothing worth showing.
///
/// Null covers three cases deliberately: the middleware sent no estimate; the
/// estimate has already passed (a header that went stale between refreshes —
/// showing "full speed in 0h" to someone still on standby is worse than showing
/// nothing); and anything unparseable, via [hubTierUntil].
///
/// Rounds UP, and floors at one hour, so the figure never under-promises. Days
/// take over at 48h, below which "2d" would lose too much precision.
({int value, bool isDays})? hubTierCountdown(DateTime? until, DateTime now) {
  if (until == null) return null;
  final remaining = until.difference(now);
  if (remaining <= Duration.zero) return null;
  if (remaining < const Duration(hours: 48)) {
    final hours = (remaining.inMinutes / 60).ceil();
    return (value: hours < 1 ? 1 : hours, isDays: false);
  }
  return (value: (remaining.inHours / 24).ceil(), isDays: true);
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
