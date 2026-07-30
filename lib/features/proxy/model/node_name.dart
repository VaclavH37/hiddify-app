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
