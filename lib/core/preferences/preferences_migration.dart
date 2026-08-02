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
      PreferencesVersion6Migration(sharedPreferences),
      PreferencesVersion7Migration(sharedPreferences),
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
        // An unrecognised stored value falls through to VPN.
        _ => "vpn",
      };
      loggy.debug("changing service-mode from [$serviceMode] to [$newMode]");
      // Superseded by v6, which deletes this key outright now that the app is
      // locked to TUN. Kept as-is rather than removed: a partially-migrated install
      // must still reach v6 through the same sequence of steps it would have before.
      await sharedPreferences.setString("service-mode", newMode);
    }

    // `ipv6-mode` backed a Settings picker that the core never read; the control
    // is gone (see singbox_config_enum.dart), so drop the key instead of
    // rewriting it. Installs already past this migration keep a dead entry that
    // nothing reads.
    await sharedPreferences.remove("ipv6-mode");

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

/// v6 — drop the stored service mode. The app is locked to TUN and the Settings
/// picker and tray submenu that set this are gone, so nothing writes the key any
/// more.
///
/// Clearing it is NOT cosmetic. Android's native side reads this SharedPreferences
/// entry directly (`flutter.service-mode` in SettingsKey.kt) to choose between
/// VPNService and ProxyService, and Dart is its only writer. An install that had
/// "proxy" or "system-proxy" stored would otherwise keep launching ProxyService —
/// no tun fd, no tunnel — forever, with no UI left to change it back. Removing the
/// key makes the Kotlin getter fall through to its own default of VPN.
///
/// Follows the `ipv6-mode` precedent in v1: drop a key that is no longer read
/// rather than rewriting it.
class PreferencesVersion6Migration extends PreferencesMigrationStep with InfraLogger {
  PreferencesVersion6Migration(super.sharedPreferences);

  @override
  Future<void> migrate() async {
    await sharedPreferences.remove("service-mode");
  }
}

/// v7 — drop the remaining Routing / DNS / Inbound settings keys.
///
/// These backed controls that were removed for one of three reasons: the core never
/// read them (`resolve-destination`, and `direct-dns-address`, whose only routing rule
/// is gated on an NTP block that is commented out); they duplicated always-on
/// behaviour (`bypass-lan`, already covered by the bundled private-address rule-set);
/// or they were live footguns (`strict-route` off is a leak, `mixed-port` changed
/// while connected sent API traffic outside the tunnel, `direct-dns-domain-strategy`
/// set to `auto` reintroduces the poisoned-AAAA bug that migration v5 exists to fix).
///
/// Every one of these values is now a constant in ConfigOptions.singboxConfigOptions,
/// set to what the default already was, so clearing the stored keys changes nothing at
/// runtime — it only stops dead entries accumulating in SharedPreferences. Purely
/// hygienic, unlike v6, which is load-bearing for Android.
class PreferencesVersion7Migration extends PreferencesMigrationStep with InfraLogger {
  PreferencesVersion7Migration(super.sharedPreferences);

  @override
  Future<void> migrate() async {
    const keysToClear = [
      // routing
      "balancer-strategy",
      "bypass-lan",
      "resolve-destination",
      // dns
      "remote-dns-address",
      "remote-dns-domain-strategy",
      "direct-dns-address",
      "direct-dns-domain-strategy",
      // inbound
      "mixed-port",
      "tproxy-port",
      "redirect-port",
      "direct-port",
      "strict-route",
      "tun-implementation",
    ];
    for (final key in keysToClear) {
      await sharedPreferences.remove(key);
    }
  }
}
