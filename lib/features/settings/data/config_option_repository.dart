import 'package:dartx/dartx.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/optional_range.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/core/utils/json_converters.dart';
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

  static final ipv6Mode = PreferencesNotifier.create<IPv6Mode, String>(
    "ipv6-mode",
    IPv6Mode.disable,
    mapFrom: (value) => IPv6Mode.values.firstWhere((e) => e.key == value),
    mapTo: (value) => value.key,
  );

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

  static final directDnsDomainStrategy = PreferencesNotifier.create<DomainStrategy, String>(
    "direct-dns-domain-strategy",
    DomainStrategy.auto,
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

  static final connectionTestUrl = PreferencesNotifier.create<String, String>(
    "connection-test-url",
    "http://captive.apple.com/hotspot-detect.html",
    possibleValues: List.of([
      "http://connectivitycheck.gstatic.com/generate_204",
      "http://www.gstatic.com/generate_204",
      "https://www.gstatic.com/generate_204",
      "https://redirector.googlevideo.com/generate_204",
      "http://cp.cloudflare.com",
      "http://kernel.org",
      "http://detectportal.firefox.com",
      "http://captive.apple.com/hotspot-detect.html",
      "https://1.1.1.1",
      "http://1.1.1.1",
    ]),
    validator: (value) => value.isNotBlank && isUrl(value),
  );

  static final urlTestInterval = PreferencesNotifier.create<Duration, int>(
    "url-test-interval",
    const Duration(minutes: 10),
    mapFrom: const IntervalInSecondsConverter().fromJson,
    mapTo: const IntervalInSecondsConverter().toJson,
  );

  static const _kClashApiPort = 16756;

  static final bypassLan = PreferencesNotifier.create<bool, bool>("bypass-lan", false);

  static final enableFakeDns = PreferencesNotifier.create<bool, bool>("enable-fake-dns", true);

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
    "ipv6-mode": ipv6Mode,
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
    "url-test-interval": urlTestInterval,
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
      resolveDestination: ref.watch(resolveDestination),
      ipv6Mode: ref.watch(ipv6Mode),
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
      enableFakeDns: ref.watch(enableFakeDns),
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
