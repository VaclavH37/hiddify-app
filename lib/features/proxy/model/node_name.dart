import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';

/// How the exit was chosen. The location card and the picker caption a
/// location with this; the automatic mode is the client-injected `urltest`
/// group ("Fastest server").
///
/// There was a second automatic mode, "Auto rotate" (the core's round-robin
/// `balance` group), until 1.6.4. A record that still carries its code
/// decodes as [chosen]; PreferencesVersion8Migration drops those records.
enum ExitMode {
  fastest,
  chosen;

  /// The caption under a location, or null when the mode adds nothing to
  /// say: a location the user chose is just the location.
  String? caption(Translations t) => switch (this) {
    fastest => t.pages.proxies.fastestServer,
    chosen => null,
  };

  /// Persisted form.
  String get code => name;

  static ExitMode fromCode(String? code) => values.firstWhere((m) => m.name == code, orElse: () => chosen);

  /// The mode a client-injected group tag stands for; null for a node.
  static ExitMode? forGroupTag(String tag) => switch (tag.toLowerCase()) {
    'lowest' => fastest,
    _ => null,
  };
}

/// Matches one or more trailing country-flag emoji (pairs of Regional Indicator
/// Symbols U+1F1E6–U+1F1FF) plus surrounding whitespace.
final RegExp _trailingFlagPattern = RegExp(r'\s*(?:[\u{1F1E6}-\u{1F1FF}]{2}\s*)+$', unicode: true);

/// Removes any trailing country-flag emoji (and surrounding whitespace) from
/// [name].
String stripTrailingFlag(String name) => name.replaceAll(_trailingFlagPattern, '').trim();

/// The role prefix the backend prepends to an exit's tag.
const String _exitTagPrefix = 'EXIT-';

/// Display form of a backend node [tag].
///
/// Strips the "EXIT-" role prefix and any trailing country-flag emoji, leaving
/// the readable portion verbatim — e.g. "EXIT-Tokyo, JP🇯🇵" -> "Tokyo, JP".
///
/// This is the ONLY processing the client applies to a node tag: the human-
/// readable name after the prefix is authored by the MW API and shown as-is (the
/// internal tag schema is intentionally NOT parsed here). The flag is dropped
/// because it is rendered separately as the leading icon, decoded from that
/// same flag by [countryCodeFromTag]; keeping it in the text would render two.
String displayNodeTag(String tag) {
  final withoutPrefix = tag.startsWith(_exitTagPrefix) ? tag.substring(_exitTagPrefix.length) : tag;
  return stripTrailingFlag(withoutPrefix);
}

/// The ISO 3166 country code encoded by the trailing flag emoji of [tag] (the
/// last pair of Regional Indicator Symbols), or null when there is none:
/// "EXIT-Tokyo, JP🇯🇵" -> "JP".
///
/// The MW API appends the flag to every exit's tag, so this is the flag's
/// source of truth. The connection probe's geolocation, which the flag used to
/// come from, is a guess about the address the probe happened to exit from:
/// empty until a node has been probed (a globe), and wrong whenever the probe
/// exits elsewhere or the geolocation database misplaces the range.
String? countryCodeFromTag(String tag) {
  final runes = tag.trimRight().runes.toList();
  if (runes.length < 2) return null;
  final a = runes[runes.length - 2];
  final b = runes[runes.length - 1];
  const first = 0x1F1E6;
  const last = 0x1F1FF;
  if (a < first || a > last || b < first || b > last) return null;
  return String.fromCharCodes([a - first + 0x41, b - first + 0x41]);
}

/// The flag to draw for an outbound: the trailing flag of its tag, or of the
/// member a group has resolved to, and only failing both the probe's
/// geolocation (empty when there is none, which draws the globe).
///
/// The raw tag is tried before the display tag because the flag can sit on
/// either side of a "§" section the core trims for display.
String flagCountryCode(OutboundInfo proxy) {
  if (proxy.isGroup) {
    final member = proxy.groupSelectedTag.split('§').first;
    return countryCodeFromTag(member) ?? countryCodeFromTag(proxy.groupSelectedTagDisplay) ?? proxy.ipinfo.countryCode;
  }
  return countryCodeFromTag(proxy.tag) ?? countryCodeFromTag(proxy.tagDisplay) ?? proxy.ipinfo.countryCode;
}

/// The picker's alphabetical order: by country code, then by display name
/// within a country, so the list reads as countries with their cities under
/// them. A node with no country (no flag and no probe) sorts last. Case is
/// ignored in the name so "amsterdam" and "Amsterdam" sit together.
int compareByCountryThenName(OutboundInfo a, OutboundInfo b) {
  final countryA = flagCountryCode(a);
  final countryB = flagCountryCode(b);
  if (countryA.isEmpty != countryB.isEmpty) return countryA.isEmpty ? 1 : -1;
  final byCountry = countryA.compareTo(countryB);
  if (byCountry != 0) return byCountry;
  return displayNodeTag(a.tag).toLowerCase().compareTo(displayNodeTag(b.tag).toLowerCase());
}

/// What a probe result means. The core reports an exit it has not probed as
/// 0 and an exit whose probe failed as the 65535 sentinel; neither is a
/// measurement, and the picker must not read either as one. The order of the
/// values is the "by latency" order.
enum DelayClass { measured, untested, failed }

DelayClass delayClassOf(int delay) => switch (delay) {
  <= 0 => DelayClass.untested,
  >= hubUrlTestTimeout => DelayClass.failed,
  _ => DelayClass.measured,
};

/// The picker's "by latency" order: measured exits fastest first, then the
/// exits the core has not probed, then the exits whose probe failed. Two
/// exits of the same unmeasured class compare equal; the comparator this
/// replaces returned -1 for two zeros, so their order depended on the input.
int compareByDelay(OutboundInfo a, OutboundInfo b) {
  final classA = delayClassOf(a.urlTestDelay);
  final classB = delayClassOf(b.urlTestDelay);
  if (classA != classB) return classA.index.compareTo(classB.index);
  if (classA != DelayClass.measured) return 0;
  return a.urlTestDelay.compareTo(b.urlTestDelay);
}

/// Derives the user-facing label and flag country code for an active outbound,
/// plus whether it resolved to a real exit location. Shared by the live tile and
/// the last-location recorder so both render identically.
///
/// `resolved` is false for the "Fastest server" group placeholder and bare
/// unnamed outbounds — e.g. before a `urltest` group has picked a member on
/// first connect — so the recorder never remembers those as a "last location".
({String name, String countryCode, bool resolved, ExitMode mode}) activeProxyDisplay(
  OutboundInfo proxy,
  Translations t,
) {
  final mode = ProxyType.fromJson(proxy.type) == ProxyType.urltest ? ExitMode.fastest : ExitMode.chosen;
  final countryCode = flagCountryCode(proxy);

  // Node tags are generated in final display form by the MW API — show them
  // verbatim. The client does NOT parse the internal tag schema (that would both
  // duplicate MW's work and encode the fleet's naming convention in the client,
  // a cohort-identification surface). A urltest group's resolved member is
  // carried on `groupSelectedTagDisplay`.
  final rawName = proxy.groupSelectedTagDisplay.isNotEmpty ? proxy.groupSelectedTagDisplay : proxy.tagDisplay;

  // The client-injected "Fastest server" group has no per-node tag until it
  // resolves a member; give it its mode label (a local group tag, not an
  // MW-issued node name) and mark it unresolved so the recorder doesn't
  // remember a placeholder.
  if (ExitMode.forGroupTag(rawName) == ExitMode.fastest) {
    return (name: t.pages.proxies.fastestServer, countryCode: countryCode, resolved: false, mode: ExitMode.fastest);
  }

  return (name: displayNodeTag(rawName), countryCode: countryCode, resolved: rawName.isNotEmpty, mode: mode);
}
