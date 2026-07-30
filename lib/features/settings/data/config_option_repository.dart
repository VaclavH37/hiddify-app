import 'dart:math';

import 'package:dartx/dartx.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
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
  static final serviceMode = PreferencesNotifier.create<ServiceMode, String>(
    "service-mode",
    ServiceMode.defaultMode,
    mapFrom: (value) => ServiceMode.choices.firstWhere((e) => e.key == value),
    mapTo: (value) => value.key,
  );

  static final balancerStrategy = PreferencesNotifier.create<BalancerStrategy, String>(
    "balancer-strategy",
    BalancerStrategy.roundRobin,
    mapFrom: (value) => BalancerStrategy.values.firstWhere((e) => e.key == value),
    mapTo: (value) => value.key,
  );

  static final blockAds = PreferencesNotifier.create<bool, bool>("block-ads", true);
  static final logLevel = PreferencesNotifier.create<LogLevel, String>(
    "log-level",
    LogLevel.warn,
    mapFrom: LogLevel.values.byName,
    mapTo: (value) => value.name,
  );

  static final resolveDestination = PreferencesNotifier.create<bool, bool>("resolve-destination", false);

  static final remoteDnsAddress = PreferencesNotifier.create<String, String>(
    "remote-dns-address",
    "https://1.1.1.1/dns-query",
    possibleValues: List.of([
      "local",
      "tcp://8.8.8.8",
      "tcp://1.1.1.1",
      "https://1.1.1.1/dns-query",
      "https://dns.cloudflare.com/dns-query",
      "tcp://4.4.2.2",
    ]),
    validator: (value) => value.isNotBlank,
  );

  static final remoteDnsDomainStrategy = PreferencesNotifier.create<DomainStrategy, String>(
    "remote-dns-domain-strategy",
    DomainStrategy.ipv4Only,
    mapFrom: (value) => DomainStrategy.values.firstWhere((e) => e.key == value),
    mapTo: (value) => value.key,
  );

  static final directDnsAddress = PreferencesNotifier.create<String, String>(
    "direct-dns-address",
    "https://dns.alidns.com/dns-query",
    // Restricted to CN-reachable resolvers. Cloudflare endpoints (1.1.1.1,
    // dns.cloudflare.com) were removed because they are GFW-throttled and
    // would silently poison direct lookups inside mainland China.
    possibleValues: List.of([
      "local",
      "https://dns.alidns.com/dns-query",
      "https://doh.pub/dns-query",
      "tcp://223.5.5.5",
    ]),
    validator: (value) => value.isNotBlank,
  );

  /// ipv4_only, matching [remoteDnsDomainStrategy]. The CN-direct resolvers
  /// return GFW-poisoned AAAA records for foreign names (www.google.com came
  /// back as the sentinel 2001::1, which the client then dialled ~200 times).
  /// `auto` applies no filtering and lets those through.
  static final directDnsDomainStrategy = PreferencesNotifier.create<DomainStrategy, String>(
    "direct-dns-domain-strategy",
    DomainStrategy.ipv4Only,
    mapFrom: (value) => DomainStrategy.values.firstWhere((e) => e.key == value),
    mapTo: (value) => value.key,
  );

  static final mixedPort = PreferencesNotifier.create<int, int>(
    "mixed-port",
    12334,
    validator: (value) => isPort(value.toString()),
  );

  static final tproxyPort = PreferencesNotifier.create<int, int>(
    "tproxy-port",
    12335,
    validator: (value) => isPort(value.toString()),
  );
  static final redirectPort = PreferencesNotifier.create<int, int>(
    "redirect-port",
    12336,
    validator: (value) => isPort(value.toString()),
  );
  static final directPort = PreferencesNotifier.create<int, int>(
    "direct-port",
    12337,
    validator: (value) => isPort(value.toString()),
  );

  static final tunImplementation = PreferencesNotifier.create<TunImplementation, String>(
    "tun-implementation",
    TunImplementation.gvisor,
    mapFrom: TunImplementation.values.byName,
    mapTo: (value) => value.name,
  );

  static final mtu = PreferencesNotifier.create<int, int>("mtu", 9000);

  static final strictRoute = PreferencesNotifier.create<bool, bool>("strict-route", true);

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

  static final bypassLan = PreferencesNotifier.create<bool, bool>("bypass-lan", false);

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
    "balancer-strategy": balancerStrategy,
    "block-ads": blockAds,
    "service-mode": serviceMode,
    "log-level": logLevel,
    "resolve-destination": resolveDestination,
    "remote-dns-address": remoteDnsAddress,
    "remote-dns-domain-strategy": remoteDnsDomainStrategy,
    "direct-dns-address": directDnsAddress,
    "direct-dns-domain-strategy": directDnsDomainStrategy,
    "mixed-port": mixedPort,
    "tproxy-port": tproxyPort,
    "direct-port": directPort,
    "redirect-port": redirectPort,
    "tun-implementation": tunImplementation,
    "mtu": mtu,
    "strict-route": strictRoute,
    "connection-test-url": connectionTestUrl,
    "bypass-lan": bypassLan,
    // "enable-dns-routing": enableDnsRouting,

    // mux
    // "mux.enable": enableMux,
    // "mux.padding": muxPadding,
    // "mux.max-streams": muxMaxStreams,
    // "mux.protocol": muxProtocol,
  };

  static final singboxConfigOptions = Provider<SingboxConfigOption>((ref) {
    final rules = <SingboxRule>[];
    final mode = ref.watch(serviceMode);

    return SingboxConfigOption(
      // Region is locked to "cn" — this app is exclusively optimized for
      // travellers / professionals in mainland China. The Go core's Region
      // branch consumes this to wire geosite-cn / geoip-cn direct routing.
      region: "cn",
      balancerStrategy: ref.watch(balancerStrategy),
      blockAds: ref.watch(blockAds),
      executeConfigAsIs: false,
      logLevel: ref.watch(logLevel),
      // Release builds write NO log file (empty = memory/console only); debug
      // and profile builds keep data/box.log for UAT. See LogFile in
      // hiddify_option.go, whose default is likewise empty.
      logFile: kReleaseMode ? "" : "data/box.log",
      resolveDestination: ref.watch(resolveDestination),
      remoteDnsAddress: ref.watch(remoteDnsAddress),
      remoteDnsDomainStrategy: ref.watch(remoteDnsDomainStrategy),
      directDnsAddress: ref.watch(directDnsAddress),
      directDnsDomainStrategy: ref.watch(directDnsDomainStrategy),
      mixedPort: ref.watch(mixedPort),
      tproxyPort: ref.watch(tproxyPort),
      directPort: ref.watch(directPort),
      redirectPort: ref.watch(redirectPort),
      tunImplementation: ref.watch(tunImplementation),
      mtu: ref.watch(mtu),
      strictRoute: ref.watch(strictRoute),
      connectionTestUrl: ref.watch(connectionTestUrl),
      urlTestInterval: ref.watch(urlTestInterval),
      enableClashApi: true,
      clashApiPort: _kClashApiPort,
      enableTun: mode == ServiceMode.tun,
      // enableTunService: mode == false, //ServiceMode.tunService,
      setSystemProxy: mode == ServiceMode.systemProxy,
      bypassLan: ref.watch(bypassLan),
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
