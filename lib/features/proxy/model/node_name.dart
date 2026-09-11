import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';

/// How the exit was chosen. The location card and the picker caption a
/// location with this; the two automatic modes are the client-injected
/// `urltest` and `balancer` groups.
enum ExitMode {
  fastest,
  rotate,
  chosen;

  /// The caption under a location, or null when the mode adds nothing to
  /// say: a location the user chose is just the location.
  String? caption(Translations t) => switch (this) {
    fastest => t.pages.proxies.fastestServer,
    rotate => t.pages.proxies.autoRotate,
    chosen => null,
  };

  /// Persisted form.
  String get code => name;

  static ExitMode fromCode(String? code) => values.firstWhere((m) => m.name == code, orElse: () => chosen);

  /// The mode a client-injected group tag stands for; null for a node.
  static ExitMode? forGroupTag(String tag) => switch (tag.toLowerCase()) {
    'lowest' => fastest,
    'balance' => rotate,
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

/// Derives the user-facing label and flag country code for an active outbound,
/// plus whether it resolved to a real exit location. Shared by the live tile and
/// the last-location recorder so both render identically.
///
/// `resolved` is false for auto-selector group placeholders ("Lowest Latency",
/// "Auto rotate") and bare unnamed outbounds — e.g. before a `urltest` group has
/// picked a member on first connect — so the recorder never remembers those as a
/// "last location".
({String name, String countryCode, bool resolved, ExitMode mode}) activeProxyDisplay(
  OutboundInfo proxy,
  Translations t,
) {
  final proxyType = ProxyType.fromJson(proxy.type);
  final mode = switch (proxyType) {
    ProxyType.urltest => ExitMode.fastest,
    ProxyType.balancer => ExitMode.rotate,
    _ => ExitMode.chosen,
  };
  final countryCode = flagCountryCode(proxy);

  // Balancer: the core doesn't populate `groupSelectedTagDisplay`, so derive the
  // resolved exit from its IP geo ("Tokyo, JP"). Without a city there's no real
  // location to show, so fall back to the mode label rather than a bare country.
  if (proxyType == ProxyType.balancer) {
    final location = _balancerMemberName(proxy) ?? _balancerLocationName(proxy);
    if (location != null) {
      return (name: location, countryCode: countryCode, resolved: true, mode: ExitMode.rotate);
    }
    return (name: t.pages.proxies.autoRotate, countryCode: countryCode, resolved: false, mode: ExitMode.rotate);
  }

  // Node tags are generated in final display form by the MW API — show them
  // verbatim. The client does NOT parse the internal tag schema (that would both
  // duplicate MW's work and encode the fleet's naming convention in the client,
  // a cohort-identification surface). A urltest group's resolved member is
  // carried on `groupSelectedTagDisplay`.
  final rawName = proxy.groupSelectedTagDisplay.isNotEmpty ? proxy.groupSelectedTagDisplay : proxy.tagDisplay;

  // Client-injected auto-selector groups have no per-node tag until they resolve
  // a member; give the known ones their mode labels (these are local group tags,
  // not MW-issued node names) and mark them unresolved so the recorder doesn't
  // remember a placeholder.
  switch (rawName.toLowerCase()) {
    case 'lowest':
      return (name: t.pages.proxies.fastestServer, countryCode: countryCode, resolved: false, mode: ExitMode.fastest);
    case 'balance':
      return (name: t.pages.proxies.autoRotate, countryCode: countryCode, resolved: false, mode: ExitMode.rotate);
  }

  return (name: displayNodeTag(rawName), countryCode: countryCode, resolved: rawName.isNotEmpty, mode: mode);
}

/// The member a balancer last handed a connection to, in display form, or
/// null when the core has not reported one.
///
/// The core sets the balancer's *display* selected tag to its strategy name
/// ("round-robin"), which is why the card used to read "Auto rotate" twice
/// over. The raw selected tag is the strategy's `Now()`, which the shipped
/// core's round-robin strategy leaves empty, so today this returns null and
/// the caller falls back to the connection probe's geo. It is here for a core
/// that does report the member; anything that is not one (empty, the
/// strategy, the group itself) counts as no report.
String? _balancerMemberName(OutboundInfo proxy) {
  // The raw tag can carry a "§" section the core trims for display.
  final raw = proxy.groupSelectedTag.split('§').first.trim();
  if (raw.isEmpty || raw == proxy.tag || raw == proxy.groupSelectedTagDisplay) return null;
  if (ExitMode.forGroupTag(raw) != null) return null;
  final name = displayNodeTag(raw);
  return name.isEmpty ? null : name;
}

/// Location for a balancer's resolved exit from its IP geo — "City, CC", or just
/// "City" when the country is missing. Returns null when there's no city to build
/// a real location (a bare country reads as a meaningless "JP"); the caller then
/// shows the "Auto rotate" mode label instead.
String? _balancerLocationName(OutboundInfo proxy) {
  final ip = proxy.ipinfo;
  final city = ip.city;
  final cc = ip.countryCode;
  if (city.isNotEmpty && cc.isNotEmpty) return '$city, $cc';
  if (city.isNotEmpty) return city;
  return null;
}
