import 'package:freezed_annotation/freezed_annotation.dart';

// `ServiceMode` used to live here: a proxy / system-proxy / vpn enum backing a
// Settings → Inbound picker and a desktop tray submenu. It is gone, and the app is
// locked to TUN — `ConfigOptions` sends `enableTun: true` / `setSystemProxy: false`
// unconditionally.
//
// It was removed because it was the most dangerous control in the settings menu, not
// merely a redundant one. "Proxy service only" cleared BOTH booleans, so the core
// built a loopback mixed inbound and nothing else: no TUN, no system proxy, nothing
// claiming the routing table — while the UI still reported Connected. On Android it
// additionally selected ProxyService over VPNService, so no tun fd was ever opened.
// Making `tun` the default fixed the fresh-install case but left the control that
// undid it reachable from two surfaces.
//
// Android's native side reads the `flutter.service-mode` SharedPreferences key
// directly (SettingsKey.kt) and Dart was its only writer, so preferences migration
// v6 clears it — the Kotlin getter then falls back to its own VPN default. If a
// service-mode concept is ever reintroduced, that native reader is the constraint to
// design around, not the Dart enum.

// `BalancerStrategy` used to live here (round-robin / consistent-hashing /
// sticky-sessions), backing a Settings → Routing picker and the `balancer-strategy`
// field on SingboxConfigOption. Both are gone and the client no longer sends the
// key at all.
//
// The picker was removed because it could not do what it claimed: it only fed the
// `balance` outbound group, which the selector does not default to, and two of its
// three options were broken anyway — builder.go never set the group's `MaxRetry`,
// so consistent-hashing degenerated to "first alive node" and sticky-sessions
// returned a time-seeded pick with no liveness check.
//
// The field then followed once the core stopped needing it: DefaultHiddifyOptions()
// sets round-robin and normalizeBalancerStrategy() in builder.go rejects anything
// unusable, so an absent key resolves correctly. Before that fix the key HAD to be
// sent — the Go default was "", which the balancer rejects with "unknown load
// balance strategy", failing service start on any profile with >1 outbound.
//
// If a strategy control is ever reintroduced, note the constraint that bit here:
// omitting the key is safe, but sending an empty string is not — it overwrites the
// core's default with the one value that cannot work.

// `IPv6Mode` used to live here, backing a Settings → Routing picker. It was
// serialised, sent to the core over gRPC and persisted — and read by nothing:
// both use sites in builder.go were commented out upstream. A security control
// that appears to work and does nothing is worse than no control, so it is
// gone rather than left in place. DNS address families remain controllable via
// remote/direct-dns-domain-strategy, which the core does read.
//
// IPv6 through the hub is a plausible future capability. The decision point
// already exists and is the ONLY one that matters: `tunnelIPv6Enabled(hopt)` in
// hiddify-core/v2/config/builder.go, which gates whether the TUN claims an IPv6
// address and therefore whether AutoRoute installs a ::/0 route into it.
//
// To wire it up:
//   1. add `TunnelIPv6` to RouteOptions in hiddify_option.go and return it from
//      condition (2) of tunnelIPv6Enabled;
//   2. prefer feeding it from the subscription — the hub knows its own egress
//      capability — over adding a user setting;
//   3. only if it must be user-visible, re-add an enum here plus a
//      PreferencesNotifier in ConfigOptions and a tile in route_options_page,
//      and cover it with a test asserting the tun address list actually changes.
//      Step 3 without step 1 recreates exactly the dead control removed here.

/// Wire mapping only — the Settings → DNS pickers that used to present these are
/// gone. `ConfigOptions` sends [ipv4Only] for both the remote and direct strategy;
/// see the comments there for why, and note that neither value decides the
/// connection's address family (the core's pre-dial `resolve` action hardcodes
/// IPv4-only). The full value set is retained because the core accepts all of them
/// and a subscription override could legitimately supply one.
@JsonEnum(valueField: 'key')
enum DomainStrategy {
  auto(""),
  preferIpv6("prefer_ipv6"),
  preferIpv4("prefer_ipv4"),
  ipv4Only("ipv4_only"),
  ipv6Only("ipv6_only");

  const DomainStrategy(this.key);

  final String key;
}

/// Wire mapping only — the Settings → Inbound picker is gone and `ConfigOptions`
/// always sends [gvisor]. Serialised by constant name, which is exactly what the
/// core's `tun-implementation` field expects.
///
/// `present()` was removed with the picker, but it had already been dead: the
/// picker rendered choices with `value.name`, not the translated labels.
enum TunImplementation { mixed, system, gvisor }

enum MuxProtocol { h2mux, smux, yamux }

@JsonEnum(valueField: 'key')
enum WarpDetourMode {
  proxyOverWarp("proxy_over_warp"),
  warpOverProxy("warp_over_proxy");

  const WarpDetourMode(this.key);

  final String key;
}
