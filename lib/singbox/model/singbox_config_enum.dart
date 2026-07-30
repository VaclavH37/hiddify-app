import 'dart:io';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/utils/platform_utils.dart';

@JsonEnum(valueField: 'key')
enum ServiceMode {
  proxy("proxy"),
  systemProxy("system-proxy"),
  tun("vpn")
  // tunService("vpn-service")
  ;

  const ServiceMode(this.key);

  final String key;

  /// Desktop used to default to [systemProxy]. That left a fresh Windows
  /// install with `enableTun == false`, so builder.go never created a TUN
  /// inbound: nothing claimed the routing table, and everything the Windows
  /// system-proxy setting does not cover — all IPv6, and any app that ignores
  /// it — went out natively while the UI reported "connected". Sensible for a
  /// general-purpose proxy client, wrong for a VPN.
  ///
  /// Only affects installs with no stored `service-mode`; an explicit choice is
  /// untouched.
  static ServiceMode get defaultMode => tun;

  /// supported service mode based on platform, use this instead of [values] in UI
  static List<ServiceMode> get choices {
    if (Platform.isWindows || Platform.isLinux) {
      return values;
    } else if (Platform.isMacOS) {
      return [proxy, systemProxy, tun];
    }
    // mobile
    return [proxy, tun];
  }

  // bool get isExperimental => switch (this) {
  //       tun => PlatformUtils.isDesktop,
  //       tunService => PlatformUtils.isDesktop,
  //       _ => false,
  //     };

  String present(TranslationsEn t) => switch (this) {
    proxy => t.pages.settings.inbound.serviceModes.proxy,
    systemProxy => t.pages.settings.inbound.serviceModes.systemProxy,
    tun => t.pages.settings.inbound.serviceModes.tun,
    // tunService => t.pages.settings.inbound.serviceModes.tunService,
  };

  String presentShort(TranslationsEn t) => switch (this) {
    proxy => t.pages.settings.inbound.shortServiceModes.proxy,
    systemProxy => t.pages.settings.inbound.shortServiceModes.systemProxy,
    tun => t.pages.settings.inbound.shortServiceModes.tun,
    // tunService => t.pages.settings.inbound.shortServiceModes.tunService,
  };
}

@JsonEnum(valueField: 'key')
enum BalancerStrategy {
  roundRobin("round-robin"),
  consistentHash("consistent-hashing"),
  stickySession("sticky-sessions");

  const BalancerStrategy(this.key);

  final String key;

  String present(TranslationsEn t) => switch (this) {
    roundRobin => t.pages.settings.routing.balancerStrategy.roundRobin,
    consistentHash => t.pages.settings.routing.balancerStrategy.consistentHash,
    stickySession => t.pages.settings.routing.balancerStrategy.stickySession,
  };
}

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

@JsonEnum(valueField: 'key')
enum DomainStrategy {
  auto(""),
  preferIpv6("prefer_ipv6"),
  preferIpv4("prefer_ipv4"),
  ipv4Only("ipv4_only"),
  ipv6Only("ipv6_only");

  const DomainStrategy(this.key);

  final String key;

  String present(TranslationsEn t) => switch (this) {
    auto => t.pages.settings.dns.domainStrategy.auto,
    preferIpv6 => t.pages.settings.dns.domainStrategy.preferIpv6,
    preferIpv4 => t.pages.settings.dns.domainStrategy.preferIpv4,
    ipv4Only => t.pages.settings.dns.domainStrategy.ipv4Only,
    ipv6Only => t.pages.settings.dns.domainStrategy.ipv6Only,
  };
}

enum TunImplementation {
  mixed,
  system,
  gvisor;

  String present(TranslationsEn t) => switch (this) {
    mixed => t.pages.settings.inbound.tunImplementations.mixed,
    system => t.pages.settings.inbound.tunImplementations.system,
    gvisor => t.pages.settings.inbound.tunImplementations.gvisor,
  };
}

enum MuxProtocol { h2mux, smux, yamux }

@JsonEnum(valueField: 'key')
enum WarpDetourMode {
  proxyOverWarp("proxy_over_warp"),
  warpOverProxy("warp_over_proxy");

  const WarpDetourMode(this.key);

  final String key;
}
