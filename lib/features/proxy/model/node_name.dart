/// Matches one or more trailing country-flag emoji (pairs of Regional Indicator
/// Symbols U+1F1E6–U+1F1FF) plus surrounding whitespace. Some backend tags
/// append a flag; we strip it because the flag is rendered separately as the
/// leading icon.
final RegExp _trailingFlagPattern = RegExp(r'\s*(?:[\u{1F1E6}-\u{1F1FF}]{2}\s*)+$', unicode: true);

final RegExp _countryCodePattern = RegExp(r'^[A-Za-z]{2}$');

/// Separator the core uses to render chained (detour) outbounds as
/// "`<primary> → <detour>`" (see hiddify-core `proxy_info.go`). Tolerates the
/// ASCII "->" form too. Used to keep only the primary hop.
final RegExp _detourSeparator = RegExp(r'\s*(?:→|->)\s*');

/// Removes any trailing country-flag emoji (and surrounding whitespace) from
/// [name].
String stripTrailingFlag(String name) => name.replaceAll(_trailingFlagPattern, '').trim();

/// Converts a backend outbound [tag] in the hub/spoke naming convention into a
/// user-readable `City, CC` label.
///
/// Recognized forms:
///   - `HUB-<CC>-<CITY>-<cohortId>` &nbsp; e.g. `HUB-JP-TOKYO-A` -> `Tokyo, JP`
///   - `EXIT-<CC>-<CITY>-<nodeId>[flag]` &nbsp; e.g. `EXIT-US-DALLAS-01🇺🇸` -> `Dallas, US`
///
/// The `CITY` may itself span multiple hyphen-separated segments for multi-word
/// cities (e.g. `EXIT-US-NEW-YORK-02` -> `New York, US`). Everything between the
/// country code and the trailing id is treated as the city.
///
/// Chained (detour) tags rendered as "`<primary> → <detour>`" use only the
/// primary hop, so an exit routed through a hub
/// (`EXIT-US-DALLAS-01🇺🇸 → HUB-JP-TOKYO-A`) still resolves to `Dallas, US`.
///
/// Returns null when [tag] doesn't match the convention, so callers can fall
/// back to their existing display logic (group names, balancer labels, etc.).
String? prettifyNodeName(String tag) {
  // Chained (detour) outbounds carry the user-facing location on the primary
  // hop only — drop everything from the first arrow onward.
  final primary = tag.split(_detourSeparator).first;
  final parts = stripTrailingFlag(primary).split('-');
  // Need at least: <prefix> - <cc> - <city…> - <id>.
  if (parts.length < 4) return null;

  final prefix = parts.first.toUpperCase();
  if (prefix != 'HUB' && prefix != 'EXIT') return null;

  final countryCode = parts[1];
  if (!_countryCodePattern.hasMatch(countryCode)) return null;

  // Everything between the country code and the trailing id is the city.
  final citySegments = parts.sublist(2, parts.length - 1).where((s) => s.isNotEmpty);
  if (citySegments.isEmpty) return null;
  final city = citySegments.map(_titleCase).join(' ');

  return '$city, ${countryCode.toUpperCase()}';
}

String _titleCase(String word) => word[0].toUpperCase() + word.substring(1).toLowerCase();
