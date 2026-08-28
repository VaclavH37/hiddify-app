import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hiddify/features/profile/model/config_slot.dart';

/// How long to wait before the confirming probe.
///
/// Long enough that a transient stall has passed, short enough that the user is
/// still in the app looking at a tunnel that is not working.
const hubConfirmDelay = Duration(seconds: 30);

/// How long a forced standby leg lasts before the client retries the primary.
///
/// Once on standby the client is not dialling the primary hub any more, so
/// neither side can observe whether the block has cleared. A lease is the only
/// mechanism available, and 12 h is the trade between churn while a block
/// persists and time spent on the inferior link after it lifts.
///
/// It is a ceiling, not a schedule. Both faster paths — the primary's address
/// changing (see [hubDigest]) and a user-initiated connect — return sooner, and
/// in practice one of them usually fires first.
const hubStandbyLease = Duration(hours: 12);

/// Minimum time on standby before a user-initiated connect retries the primary.
///
/// Without it, a user toggling the VPN because it is not working gets a broken
/// primary attempt on every single toggle. With it the first toggle retries the
/// primary — the point of the feature, since the block may have cleared — and
/// any toggle in the next quarter hour goes straight to the link that works.
const hubRetryPrimaryFloor = Duration(minutes: 15);

/// Slot flips permitted inside [hubFlapWindow].
///
/// The backstop for a primary hub that is intermittently reachable: enough of
/// the probe window to pass for the ladder to fail over, enough to fail the
/// confirming probe and revert, repeatedly. Each flip restarts the core and
/// drops every live connection, so an oscillation is far worse for the user
/// than simply staying put on either hub.
///
/// Four is deliberately loose. It has to leave room for the legitimate
/// sequence — fail over, confirm, revert because the device was offline — to
/// happen more than once a day without tripping.
const hubFlapCap = 4;

/// The window [hubFlapCap] is counted over.
const hubFlapWindow = Duration(hours: 24);

/// How long to wait after a failover that REVERTED before attempting another.
///
/// A revert means neither hub carried traffic, i.e. the device was offline
/// rather than the primary being blocked. Offline persists for minutes or
/// hours, so without this every refresh cycle would repeat the whole sequence —
/// two probes, a restart onto standby, a probe, a restart back — to re-learn a
/// fact that has not changed. Two core restarts per cycle, each dropping every
/// live connection, is a heavy price for a device that cannot reach anything.
///
/// A failover that SUCCEEDS never sets this: the client is on standby and the
/// return path runs from then on instead.
const hubOfflineBackoff = Duration(hours: 1);

/// When a failover last reverted for want of any working hub.
const hubOfflineBackoffKey = 'hub_offline_backoff_at';

/// Whether enough time has passed since a reverted failover to probe again.
bool failoverAttemptDue(DateTime? lastRevertAt, DateTime now) {
  if (lastRevertAt == null) return true;
  final elapsed = now.difference(lastRevertAt);
  return elapsed.isNegative || elapsed >= hubOfflineBackoff;
}

/// When the current forced standby leg began. Absent means we are not on a
/// forced standby leg — which is not the same as being on the primary hub, as
/// the middleware can serve standby outbounds for quota reasons entirely
/// independently (see [ConfigSlot]).
const hubStandbySinceKey = 'hub_standby_since';

/// Fingerprint of the primary config in force when we failed away from it, so
/// a later refresh can notice the hub moved. See [hubDigest].
const hubPrimaryDigestKey = 'hub_primary_digest';

/// ISO-8601 instants of recent slot flips, for the flap cap.
const hubFlipsKey = 'hub_slot_flips';

/// Request header carrying a reachability report to the middleware.
///
/// Lowercase to match the response-header convention, and because the
/// middleware's allow-list matching is case-sensitive.
const hubSignalHeader = 'x-rayn-hub-signal';

/// What the client is telling the middleware about the primary hub.
///
/// Purely informational since failover became local. The client has already
/// switched hubs by the time it sends one of these; the middleware aggregates
/// them per cohort so that "many subscribers on cohort A cannot reach the
/// primary" becomes an ops alert. Nothing the middleware does with a signal
/// changes what this client does next.
enum HubSignal {
  /// The primary hub stopped carrying traffic and the standby hub does. Sent
  /// over the standby tunnel, after the switch has already happened.
  unreachable('unreachable'),

  /// The client is back on the primary hub and it is carrying traffic. The only
  /// way the middleware ever learns a block has lifted.
  recovered('recovered');

  const HubSignal(this.wireValue);

  final String wireValue;
}

/// Whether a confirmed detection may actually move this client to standby.
///
/// Detection and permission are separate on purpose. The probe result says the
/// hub is dead; this says whether failing over would help. Both must hold, and
/// when this refuses the right outcome is to stay put and log — a client with
/// no usable standby config is better off on a dead primary it can still
/// refresh from than restarted onto nothing.
bool failoverAllowed({required ConfigSlot slot, required bool hasStandbyCache, required int recentFlipCount}) {
  if (slot != ConfigSlot.primary) return false;
  if (!hasStandbyCache) return false;
  return recentFlipCount < hubFlapCap;
}

/// Whether a forced standby leg has run its course.
///
/// A null [standbySince] means the leg has no recorded start — a preference
/// cleared underneath us, or a build that predates this key. Treated as expired
/// so the client returns to the primary and re-derives its state from a fresh
/// observation, rather than sitting on standby forever with nothing to time out.
bool standbyLeaseExpired(DateTime? standbySince, DateTime now) {
  if (standbySince == null) return true;
  final elapsed = now.difference(standbySince);
  return elapsed.isNegative || elapsed >= hubStandbyLease;
}

/// Whether a user-initiated connect should retry the primary hub.
///
/// Null [standbySince] means we are not on a forced standby leg, so there is
/// nothing to retry.
bool retryPrimaryDue(DateTime? standbySince, DateTime now) {
  if (standbySince == null) return false;
  final elapsed = now.difference(standbySince);
  return elapsed.isNegative || elapsed >= hubRetryPrimaryFloor;
}

/// The slot flips still inside [hubFlapWindow].
///
/// Unparseable entries are dropped rather than treated as recent: the list is
/// only ever written by this client, so a bad entry means corruption, and
/// counting corruption toward a cap that suppresses failover would disable the
/// feature silently.
///
/// So are FUTURE entries. A device clock that jumps forward stamps flips ahead
/// of real time, and those would otherwise sit in the window suppressing
/// failover until the clock caught up — potentially for years.
List<DateTime> recentFlips(List<String>? raw, DateTime now) =>
    (raw ?? const []).map(DateTime.tryParse).whereType<DateTime>().where((at) {
      final age = now.difference(at);
      return !age.isNegative && age < hubFlapWindow;
    }).toList();

/// A stable fingerprint of the hub addresses a config dials.
///
/// The distinct outbound `server` values, sorted, hashed. Each part earns its
/// place:
///
/// * **Distinct and sorted**, because outbound order and count vary between
///   responses for reasons that have nothing to do with the hub — the
///   middleware re-tags and re-groups exits continuously — while the address
///   set changes only when the hub actually moves.
/// * **Hashed**, because this is written to a preference file and quoted in
///   logs. The hub address is the single most sensitive value in the config and
///   it must not leak through the mechanism that watches it.
///
/// Returns null when the config cannot be read as one, which callers must treat
/// as "no opinion" rather than as "changed" — a parse failure is not evidence
/// the hub moved.
String? hubDigest(String configJson) {
  try {
    final decoded = jsonDecode(configJson);
    if (decoded is! Map) return null;
    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return null;
    final servers =
        outbounds
            .whereType<Map>()
            .map((outbound) => outbound['server'])
            .whereType<String>()
            .where((server) => server.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (servers.isEmpty) return null;
    return sha256.convert(utf8.encode(servers.join('\n'))).toString().substring(0, 16);
  } catch (_) {
    return null;
  }
}

/// Whether the primary hub has moved since we failed away from it.
///
/// The operator rotates a hub's address when it is blocked, so a changed
/// address is the block being answered — and the fastest signal the client
/// gets that the primary is worth retrying. Requires BOTH digests: absent
/// either way means no opinion, never "changed".
bool primaryHubMoved(String? storedDigest, String? currentDigest) {
  if (storedDigest == null || currentDigest == null) return false;
  return storedDigest != currentDigest;
}
