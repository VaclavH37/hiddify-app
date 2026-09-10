import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/singbox/model/singbox_proxy_type.dart';

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
/// because it is rendered separately as the leading icon (from geo-IP); keeping
/// it in the text would render two flags.
String displayNodeTag(String tag) {
  final withoutPrefix = tag.startsWith(_exitTagPrefix) ? tag.substring(_exitTagPrefix.length) : tag;
  return stripTrailingFlag(withoutPrefix);
}

/// Derives the user-facing label and flag country code for an active outbound,
/// plus whether it resolved to a real exit location. Shared by the live tile and
/// the last-location recorder so both render identically.
///
/// `resolved` is false for auto-selector group placeholders ("Lowest Latency",
/// "Auto rotate") and bare unnamed outbounds — e.g. before a `urltest` group has
/// picked a member on first connect — so the recorder never remembers those as a
/// "last location".
({String name, String countryCode, bool resolved, bool isAutoSelected}) activeProxyDisplay(
  OutboundInfo proxy,
  Translations t,
) {
  final proxyType = ProxyType.fromJson(proxy.type);
  final isAutoSelected = proxyType == ProxyType.urltest || proxyType == ProxyType.balancer;
  final countryCode = proxy.ipinfo.countryCode;

  // Balancer: the core doesn't populate `groupSelectedTagDisplay`, so derive the
  // resolved exit from its IP geo ("Tokyo, JP"). Without a city there's no real
  // location to show, so fall back to the mode label rather than a bare country.
  if (proxyType == ProxyType.balancer) {
    final location = _balancerLocationName(proxy);
    if (location != null) {
      return (name: location, countryCode: countryCode, resolved: true, isAutoSelected: true);
    }
    return (name: t.pages.proxies.autoRotate, countryCode: countryCode, resolved: false, isAutoSelected: true);
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
      return (name: t.pages.proxies.lowestLatency, countryCode: countryCode, resolved: false, isAutoSelected: true);
    case 'balance':
      return (name: t.pages.proxies.autoRotate, countryCode: countryCode, resolved: false, isAutoSelected: true);
  }

  return (
    name: displayNodeTag(rawName),
    countryCode: countryCode,
    resolved: rawName.isNotEmpty,
    isAutoSelected: isAutoSelected,
  );
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
