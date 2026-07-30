import 'package:hiddify/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesMigration with InfraLogger {
  PreferencesMigration({required this.sharedPreferences});

  final SharedPreferences sharedPreferences;

  static const versionKey = "preferences_version";

  Future<void> migrate() async {
    final currentVersion = sharedPreferences.getInt(versionKey) ?? 0;

    final migrationSteps = <PreferencesMigrationStep>[
      PreferencesVersion1Migration(sharedPreferences),
      PreferencesVersion2Migration(sharedPreferences),
      PreferencesVersion3Migration(sharedPreferences),
      PreferencesVersion4Migration(sharedPreferences),
      PreferencesVersion5Migration(sharedPreferences),
    ];

    if (currentVersion == migrationSteps.length) {
      loggy.debug("already using the latest version (v$currentVersion)");
      return;
    }

    final stopWatch = Stopwatch()..start();
    loggy.debug("migrating from v[$currentVersion] to v[${migrationSteps.length}]");
    for (int i = currentVersion; i < migrationSteps.length; i++) {
      loggy.debug("step [$i](v${i + 1})");
      await migrationSteps[i].migrate();
      await sharedPreferences.setInt(versionKey, i + 1);
    }
    stopWatch.stop();
    loggy.debug("migration took [${stopWatch.elapsedMilliseconds}]ms");
  }
}

abstract interface class PreferencesMigrationStep {
  PreferencesMigrationStep(this.sharedPreferences);

  final SharedPreferences sharedPreferences;

  Future<void> migrate();
}

class PreferencesVersion1Migration extends PreferencesMigrationStep with InfraLogger {
  PreferencesVersion1Migration(super.sharedPreferences);

  @override
  Future<void> migrate() async {
    if (sharedPreferences.getString("service-mode") case final String serviceMode) {
      final newMode = switch (serviceMode) {
        "proxy" || "system-proxy" || "vpn" => serviceMode,
        "systemProxy" => "system-proxy",
        "tun" => "vpn",
        _ => PlatformUtils.isDesktop ? "system-proxy" : "vpn",
      };
      loggy.debug("changing service-mode from [$serviceMode] to [$newMode]");
      await sharedPreferences.setString("service-mode", newMode);
    }

    if (sharedPreferences.getString("ipv6-mode") case final String ipv6Mode) {
      loggy.debug("changing ipv6-mode from [$ipv6Mode] to [${_ipv6Mapper(ipv6Mode)}]");
      await sharedPreferences.setString("ipv6-mode", _ipv6Mapper(ipv6Mode));
    }

    if (sharedPreferences.getString("remote-domain-dns-strategy") case final String remoteDomainStrategy) {
      loggy.debug(
        "changing [remote-domain-dns-strategy] = [$remoteDomainStrategy] to [remote-dns-domain-strategy] = [${_domainStrategyMapper(remoteDomainStrategy)}]",
      );
      await sharedPreferences.remove("remote-domain-dns-strategy");
      await sharedPreferences.setString("remote-dns-domain-strategy", _domainStrategyMapper(remoteDomainStrategy));
    }

    if (sharedPreferences.getString("direct-domain-dns-strategy") case final String directDomainStrategy) {
      loggy.debug(
        "changing [direct-domain-dns-strategy] = [$directDomainStrategy] to [direct-dns-domain-strategy] = [${_domainStrategyMapper(directDomainStrategy)}]",
      );
      await sharedPreferences.remove("direct-domain-dns-strategy");
      await sharedPreferences.setString("direct-dns-domain-strategy", _domainStrategyMapper(directDomainStrategy));
    }

    if (sharedPreferences.getInt("localDns-port") case final int directPort) {
      loggy.debug("changing [localDns-port] to [direct-port]");
      await sharedPreferences.remove("localDns-port");
      await sharedPreferences.setInt("direct-port", directPort);
    }

    await sharedPreferences.remove("execute-config-as-is");
    await sharedPreferences.remove("enable-tun");
    await sharedPreferences.remove("set-system-proxy");

    await sharedPreferences.remove("cron_profiles_update");
  }

  String _ipv6Mapper(String persisted) => switch (persisted) {
    "ipv4_only" || "prefer_ipv4" || "prefer_ipv4" || "ipv6_only" => persisted,
    "disable" => "ipv4_only",
    "enable" => "prefer_ipv4",
    "prefer" => "prefer_ipv6",
    "only" => "ipv6_only",
    _ => "ipv4_only",
  };

  String _domainStrategyMapper(String persisted) => switch (persisted) {
    "ipv4_only" || "prefer_ipv4" || "prefer_ipv4" || "ipv6_only" => persisted,
    "auto" => "",
    "preferIpv6" => "prefer_ipv6",
    "preferIpv4" => "prefer_ipv4",
    "ipv4Only" => "ipv4_only",
    "ipv6Only" => "ipv6_only",
    _ => "",
  };
}

/// v2 — drop user-controlled advanced toggles (xray, WARP, Clash API port) and
/// reset DNS defaults so existing installs pick up the China-optimized values.
class PreferencesVersion2Migration extends PreferencesMigrationStep with InfraLogger {
  PreferencesVersion2Migration(super.sharedPreferences);

  @override
  Future<void> migrate() async {
    const keysToClear = [
      // removed advanced toggles
      "use-xray-core-when-possible",
      "enable-clash-api",
      "clash-api-port",
      // WARP — toggle, modes, credentials, knobs
      "enable-warp",
      "warp-detour-mode",
      "warp-license-key",
      "warp2s-license-key",
      "warp-account-id",
      "warp2-account-id",
      "warp-access-token",
      "warp2-access-token",
      "warp-clean-ip",
      "warp-port",
      "warp-noise",
      "warp-noise-mode",
      "warp-noise-delay",
      "warp-noise-size",
      "warp-wireguard-config",
      "warp2-wireguard-config",
      "warp-consent-given",
      // defaults changed for China optimization
      "remote-dns-address",
      "direct-dns-address",
      "remote-dns-domain-strategy",
      "enable-fake-dns",
      "block-ads",
    ];
    for (final key in keysToClear) {
      await sharedPreferences.remove(key);
    }
  }
}

/// v3 — reset the connection-test URL so existing installs stop probing a
/// plaintext, captive-portal-branded endpoint. These probes are dialled through
/// the outbound directly and therefore cross the tunnel (url-test bypasses the
/// route table), so a recurring cleartext request to a well-known captive-portal
/// URL is a usable behavioural signature. The new default is HTTPS.
class PreferencesVersion3Migration extends PreferencesMigrationStep with InfraLogger {
  PreferencesVersion3Migration(super.sharedPreferences);

  @override
  Future<void> migrate() async {
    const keysToClear = [
      "connection-test-url",
    ];
    for (final key in keysToClear) {
      await sharedPreferences.remove(key);
    }
  }
}

/// v4 — reset the connection-test URL again. v3's replacement
/// (`https://www.gstatic.com/generate_204`) was a serious mistake: the core
/// force-pins every probe hostname to the CN-direct resolver with a 24h TTL,
/// and that cached answer is shared with normal browser traffic. gstatic is
/// GFW-poisoned, so it resolved to a China Telecom address and broke google.com
/// page loads. The default is now a host that resolves correctly via a mainland
/// resolver. Any install carrying the bad value must drop it.
class PreferencesVersion4Migration extends PreferencesMigrationStep with InfraLogger {
  PreferencesVersion4Migration(super.sharedPreferences);

  @override
  Future<void> migrate() async {
    const keysToClear = [
      "connection-test-url",
    ];
    for (final key in keysToClear) {
      await sharedPreferences.remove(key);
    }
  }
}

/// v5 — reset the direct DNS domain strategy so existing installs pick up
/// `ipv4_only`. The previous default (`auto`) applied no filtering to answers
/// from the CN-direct resolvers, which return GFW-poisoned AAAA records for
/// foreign names — www.google.com resolved to the sentinel `2001::1` and the
/// client dialled it ~200 times. The remote resolver was already `ipv4_only`;
/// this removes the inconsistency.
class PreferencesVersion5Migration extends PreferencesMigrationStep with InfraLogger {
  PreferencesVersion5Migration(super.sharedPreferences);

  @override
  Future<void> migrate() async {
    const keysToClear = [
      "direct-dns-domain-strategy",
    ];
    for (final key in keysToClear) {
      await sharedPreferences.remove(key);
    }
  }
}
