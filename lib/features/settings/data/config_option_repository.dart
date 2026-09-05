import 'dart:math';

import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/optional_range.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/settings/model/config_option_failure.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/singbox_rule.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ConfigOptions {
  static final blockAds = PreferencesNotifier.create<bool, bool>("block-ads", true);
  static final logLevel = PreferencesNotifier.create<LogLevel, String>(
    "log-level",
    LogLevel.warn,
    mapFrom: LogLevel.values.byName,
    mapTo: (value) => value.name,
  );

  /// Loopback port for the core's mixed (HTTP+SOCKS) inbound.
  ///
  /// No longer user-editable. The app proxies its OWN HTTP traffic through this
  /// port (see http_client_provider), but the core only rebinds its listener on
  /// restart — so changing it while connected desynchronised the two: `isPortOpen`
  /// failed and every subscription/API fetch silently fell back to `DIRECT`,
  /// outside the tunnel. A fixed port removes that whole class of bug.
  ///
  /// The trade-off is that a port conflict is now unrecoverable from the UI. If
  /// that ever shows up in the field, the fix is automatic port selection in the
  /// core — not restoring the setting.
  static const kMixedPort = 12334;

  static final mtu = PreferencesNotifier.create<int, int>("mtu", 9000);

  /// Latency/health probe target.
  ///
  /// CRITICAL: the core force-pins this HOSTNAME to the CN-direct resolver
  /// (doh.pub) with a 24h TTL, and that cached answer is shared with ordinary
  /// browser traffic. A GFW-poisoned host here therefore breaks real page loads,
  /// not just the probe — `www.gstatic.com` resolved to a China Telecom address
  /// and took google.com down with it. Only offer hosts that resolve CORRECTLY
  /// via a mainland resolver, or IP literals (which are exempt from the pinning).
  /// HTTPS only.
  static final connectionTestUrl = PreferencesNotifier.create<String, String>(
    "connection-test-url",
    "https://cp.cloudflare.com",
    possibleValues: List.of([
      "https://cp.cloudflare.com",
      "https://1.1.1.1",
      "https://captive.apple.com/hotspot-detect.html",
    ]),
    validator: (value) => value.isNotBlank && isUrl(value),
  );

  /// Interval for the core's `urltest` outbound group (auto "Lowest Latency"
  /// reselection). No longer a user setting — a per-session random value in
  /// [20, 40] minutes, drawn once at app launch and held stable for the session.
  ///
  /// Randomizing avoids shipping a fixed, well-known interval and de-synchronizes
  /// the periodic test bursts across installs; holding it stable within a session
  /// avoids churning the core config. The core applies this as a *fixed* interval,
  /// so true per-cycle jitter would require a core-side change — out of scope here.
  static final urlTestInterval = Provider<Duration>(
    (ref) => Duration(minutes: 20 + Random().nextInt(21)),
  );

  static const _kClashApiPort = 16756;

  // enableFakeDns preference removed: the hub runs domainStrategy:AsIs and needs
  // real IPs, so FakeIP is force-disabled in the core regardless of any option.
  // The DNS-page toggle was removed with it; enable-fake-dns is cleared from
  // stored prefs by preferences_migration.dart.

  // static final enableDnsRouting = PreferencesNotifier.create<bool, bool>("enable-dns-routing", true);

  static final independentDnsCache = PreferencesNotifier.create<bool, bool>("independent-dns-cache", true);

  // TLS tricks (fragment / mixed-SNI / padding) are forced off — they conflict
  // with REALITY-VISION-XTLS + uTLS fingerprinting.
  static const _disabledTlsTricks = SingboxTlsTricks(
    enableFragment: false,
    fragmentSize: OptionalRange(min: 10, max: 30),
    fragmentSleep: OptionalRange(min: 2, max: 8),
    mixedSniCase: false,
    enablePadding: false,
    paddingSize: OptionalRange(min: 1, max: 1500),
  );

  static final enableMux = PreferencesNotifier.create<bool, bool>("enable-mux", false);

  static final muxPadding = PreferencesNotifier.create<bool, bool>("mux-padding", false);

  static final muxMaxStreams = PreferencesNotifier.create<int, int>(
    "mux-max-streams",
    8,
    validator: (value) => value > 0,
  );

  static final muxProtocol = PreferencesNotifier.create<MuxProtocol, String>(
    "mux-protocol",
    MuxProtocol.h2mux,
    mapFrom: MuxProtocol.values.byName,
    mapTo: (value) => value.name,
  );

  static const _disabledWarp = SingboxWarpOption(
    enable: false,
    mode: WarpDetourMode.warpOverProxy,
    wireguardConfig: "",
    licenseKey: "",
    accountId: "",
    accessToken: "",
    cleanIp: "auto",
    cleanPort: 0,
    noise: OptionalRange(min: 1, max: 3),
    noiseMode: "m4",
    noiseSize: OptionalRange(min: 10, max: 30),
    noiseDelay: OptionalRange(min: 10, max: 30),
  );

  static final hasExperimentalFeatures = Provider.autoDispose<bool>((ref) {
    // final mode = ref.watch(serviceMode);
    // if (PlatformUtils.isDesktop && mode == ServiceMode.tun) {
    //   return true;
    // }
    // if (ref.watch(enableTlsFragment) || ref.watch(enableTlsMixedSniCase) || ref.watch(enableTlsPadding) || ref.watch(enableMux) || ref.watch(enableWarp) || ref.watch(bypassLan)) {
    //   return true;
    // }

    return false;
  });

  /// preferences to exclude from share and export
  static final privatePreferencesKeys = <String>{};

  static final Map<String, StateNotifierProvider<PreferencesNotifier, dynamic>> preferences = {
    "block-ads": blockAds,
    "log-level": logLevel,
    "mtu": mtu,
    "connection-test-url": connectionTestUrl,
    // "enable-dns-routing": enableDnsRouting,

    // mux
    // "mux.enable": enableMux,
    // "mux.padding": muxPadding,
    // "mux.max-streams": muxMaxStreams,
    // "mux.protocol": muxProtocol,
  };

  static final singboxConfigOptions = Provider<SingboxConfigOption>((ref) {
    final rules = <SingboxRule>[];

    return SingboxConfigOption(
      // Region is locked to "cn" — this app is exclusively optimized for
      // travellers / professionals in mainland China. The Go core's Region
      // branch consumes this to wire geosite-cn / geoip-cn direct routing.
      region: "cn",
      // `balancer-strategy` is deliberately absent from this payload. It fed the
      // `balance` outbound group, which the selector does not default to, so it did
      // nothing unless the user chose "Auto rotate" — and its picker was removed.
      //
      // Omitting the key is now safe because the core supplies it: settings are
      // unmarshalled OVER DefaultHiddifyOptions(), which sets round-robin, and
      // normalizeBalancerStrategy in builder.go rejects anything unusable at the
      // point of use. Sending an empty string would NOT be equivalent — that
      // overwrites the good default with the exact value the balancer rejects.
      blockAds: ref.watch(blockAds),
      executeConfigAsIs: false,
      // Release builds are pinned to `warn`, and the picker is compiled out of the
      // UI (see settings_page.dart). Both halves are required: hiding the tile alone
      // would leave a previously-stored `trace` flowing to the core forever, since
      // this is a persisted preference and the level is what actually dictates what
      // the core emits — independently of the debug flag.
      //
      // Why it matters at `info` and below: sing-box logs `inbound/outbound
      // connection to <destination>` at INFO and DNS `lookup domain` / `exchange` at
      // DEBUG, so anything under `warn` turns the log into a browsing history plus a
      // description of the DNS and routing design. `debug`/`trace` additionally set
      // static.debug in the core (buildconfighelper.go), which is what used to
      // trigger the goroutine dump.
      logLevel: kDebugMode ? ref.watch(logLevel) : LogLevel.warn,
      // Release builds write NO log file (empty = memory/console only); debug
      // and profile builds keep data/box.log for UAT. See LogFile in
      // hiddify_option.go, whose default is likewise empty.
      logFile: Constants.diagnosticsBuild ? "data/box.log" : "",
      // `resolve-destination` is no longer sent: the core dropped the option
      // entirely, since builder.go never read it and the behaviour its name promised
      // (resolving tunnel-bound domains client-side) is unconditional anyway.
      // The four DNS settings below were user-editable on a Settings → DNS page.
      // That page is gone: the resolver design is dictated by the hub topology
      // (domainStrategy:AsIs, CN-direct split) and tuned by the backend, not the
      // user. Values here are the previous defaults, so nothing changes at runtime.
      //
      // The backend keeps control: `remote-dns-address` and `direct-dns-address` are
      // in ProfileParser.allowedOverrideConfigs, and the override is merged over this
      // serialised map — so a subscription can still set them without a client build.
      //
      // Resolver for everything that goes through the tunnel. The dropdown this
      // replaces also offered "local", which selects sing-box's local server type —
      // i.e. the system/ISP resolver — a DNS leak that was two taps away.
      remoteDnsAddress: "https://1.1.1.1/dns-query",
      // ipv4_only. Note this does NOT decide the connection's address family: the
      // pre-dial `resolve` route action in builder.go hardcodes IPv4-only. Keeping
      // this aligned with that hardcode is the point — divergence only desynchronised
      // the DNS rules from the resolve action.
      remoteDnsDomainStrategy: DomainStrategy.ipv4Only,
      // Registered as the `dns-direct` server, but no live rule routes queries to it:
      // the one rule that did is gated on NTP, and setNTP is commented out in the
      // core. Real direct resolution uses the core's hardcoded CN resolvers
      // (doh.pub, AliDNS). Kept at the previous default so the server list is
      // unchanged; it is not a control.
      directDnsAddress: "https://dns.alidns.com/dns-query",
      // ipv4_only, matching [remoteDnsDomainStrategy]. The CN-direct resolvers return
      // GFW-poisoned AAAA records for foreign names (www.google.com came back as the
      // sentinel 2001::1, which the client then dialled ~200 times). `auto` applies no
      // filtering and lets those through — migration v5 exists to undo exactly that,
      // and the removed picker let a user set it straight back.
      directDnsDomainStrategy: DomainStrategy.ipv4Only,
      // The four listener ports below were user-editable on the Inbound page. All
      // four are loopback-bound and none is something a user of this client has a
      // reason to change; see [kMixedPort] for the one that was actively harmful.
      mixedPort: kMixedPort,
      // Linux-only, and additionally requires root (the core checks IsAdmin), so on
      // a normal run this value is accepted and ignored. Previous default kept.
      tproxyPort: 12335,
      // Linux/macOS only. Inert either way: nothing in this fork installs the
      // pf/iptables rules that would feed a redirect listener. Previous default kept.
      redirectPort: 12336,
      // 0 disables the listener entirely — the one deliberate behaviour change here.
      // This built a `direct` inbound tagged `dns-in` with no OverrideAddress,
      // OverridePort or Network set, so it forwarded to its own listen address; and
      // no route rule or DNS rule in the core references that tag. It is the vestige
      // of a local-DNS listener that was removed (hence the old `localDns-port` key).
      // The core guards on `DirectPort > 0`, and standalone instances already force
      // it to 0, so this just stops opening a socket that did nothing.
      directPort: 0,
      // Hardcoded gvisor — UI picker and preference removed, preserving the previous
      // default. The picker offered all three stacks on every platform and the core
      // passes this string straight to sing-box with no validation or fallback, so a
      // wrong pick could leave the tunnel up but not forwarding. Note the core's own
      // default is "mixed"; gvisor is this client's choice and must keep being sent.
      tunImplementation: TunImplementation.gvisor,
      mtu: ref.watch(mtu),
      // Hardcoded true — UI toggle and preference removed, preserving the previous
      // default. Strict route is what stops traffic escaping the tun via a manually
      // bound interface or a policy route; in a locked-down VPN client there is no
      // legitimate reason to turn it off, and the tile carried no warning that doing
      // so opened a leak. Read by the core only when the tun inbound is built.
      strictRoute: true,
      connectionTestUrl: ref.watch(connectionTestUrl),
      urlTestInterval: ref.watch(urlTestInterval),
      enableClashApi: true,
      clashApiPort: _kClashApiPort,
      // The app is locked to TUN. These two booleans used to be fanned out from a
      // user-facing "Service mode" picker (Proxy / System proxy / VPN), which was the
      // worst control in the settings menu: choosing "Proxy service only" set BOTH to
      // false, so the core built nothing but a loopback mixed inbound — no TUN, no
      // system proxy, nothing claiming the routing table — while the UI still reported
      // Connected. On Android it also switched the foreground service away from
      // VpnService entirely, so no tun fd was ever opened.
      //
      // ServiceMode.defaultMode was moved to `tun` earlier to fix that by default; the
      // control that could undo it is now gone from both the settings page and the
      // desktop tray. The stored `service-mode` key is cleared by migration v6 so
      // Android's native reader falls back to its own VPN default.
      enableTun: true,
      // enableTunService: false — the Go field exists but the Dart model field is
      // commented out, so it is never sent and is permanently false.
      setSystemProxy: false,
      // Hardcoded false — UI toggle and preference removed, preserving the previous
      // default. The toggle was redundant: `direct-private.srs` ships in the bundled
      // rule-sets and is applied unconditionally by the always-on China-direct route
      // rule, so RFC1918 destinations already go direct with this off. Turning it on
      // only added an earlier, duplicate rule using sing-box's built-in private check.
      bypassLan: false,
      // Hardcoded false — UI toggle removed; LAN sharing kept off by default.
      allowConnectionFromLan: false,
      // Hardcoded false — FakeIP is force-disabled (hub is domainStrategy:AsIs);
      // UI toggle and preference removed. The core ignores this value regardless.
      enableFakeDns: false,
      // enableDnsRouting: ref.watch(enableDnsRouting),
      independentDnsCache: ref.watch(independentDnsCache),
      // mux: SingboxMuxOption(
      //   enable: ref.watch(enableMux),
      //   padding: ref.watch(muxPadding),
      //   maxStreams: ref.watch(muxMaxStreams),
      //   protocol: ref.watch(muxProtocol),
      // ),
      tlsTricks: _disabledTlsTricks,
      warp: _disabledWarp,
      warp2: _disabledWarp,
      rules: rules,
    );
  });
}

class ConfigOptionRepository with ExceptionHandler, InfraLogger {
  ConfigOptionRepository({required this.preferences, required SingboxConfigOption Function() getConfigOptions})
    : _getConfigOptions = getConfigOptions;

  final SharedPreferences preferences;
  final SingboxConfigOption Function() _getConfigOptions;

  Either<ConfigOptionFailure, SingboxConfigOption> fullOptions() =>
      Either.tryCatch(() => _getConfigOptions(), ConfigOptionFailure.unexpected);

  Either<ConfigOptionFailure, SingboxConfigOption> fullOptionsOverrided(String? profileOverride) =>
      Either.tryCatch(() => _getConfigOptions(), ConfigOptionFailure.unexpected).flatMap(
        (options) => Either.tryCatch(() {
          final json = ProfileParser.applyProfileOverride(options.toJson(), profileOverride);
          return SingboxConfigOption.fromJson(json);
        }, ConfigOptionFailure.unexpected),
      );
}
