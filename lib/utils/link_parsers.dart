import 'dart:convert';

import 'package:hiddify/utils/rayn_token.dart';
import 'package:hiddify/utils/validators.dart';

typedef ProfileLink = ({String url, String name});

// TODO: test and improve
abstract class LinkParser {
  static String generateSubShareLink(String url, [String? name]) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final modifiedUri = Uri(
      scheme: uri.scheme,
      host: uri.host,
      path: uri.path,
      query: uri.query,
      fragment: name ?? uri.fragment,
    );
    // return 'hiddify://import/$modifiedUri';
    return '$modifiedUri';
  }

  // protocols schemas
  static const protocols = ['hiddify', 'v2ray', 'v2rayn', 'v2rayng', 'clash', 'clashmeta', 'sing-box', 'rayn'];

  static ProfileLink? parse(String link) {
    return simple(link) ?? deep(link);
  }

  static ProfileLink? simple(String link) {
    if (!isUrl(link)) return null;
    final uri = Uri.parse(link.trim());
    return (url: uri.toString(), name: uri.queryParameters['name'] ?? '');
  }

  static ProfileLink? deep(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    final queryParams = uri.queryParameters;
    switch (uri.scheme) {
      case 'hiddify':
        if (queryParams.containsKey('url')) {
          return (url: queryParams['url']!, name: queryParams['name'] ?? '');
        } else {
          return (url: uri.path.substring(1) + (uri.hasQuery ? "?${uri.query}" : ""), name: uri.fragment);
        }
      case 'v2ray' || 'v2rayn' || 'v2rayng' || 'clash' || 'clashmeta' || 'sing-box':
        return queryParams.containsKey('url') ? (url: queryParams['url']!, name: queryParams['name'] ?? '') : null;
      case 'rayn':
        // Format: rayn://import/<base64url_token>
        // The token MUST live in the path, not the authority — Dart's
        // `Uri.host` is normalized to lowercase, which corrupts the
        // case-sensitive base64url payload. The path component preserves
        // case, mirroring the existing `hiddify://import/<sublink>` shape.
        if (uri.host != 'import') return null;
        final encoded = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
        if (encoded.isEmpty) return null;
        final decrypted = RaynTokenDecryptor.decryptToUrl(encoded);
        if (decrypted == null) return null;
        return simple(decrypted);
      default:
        return null;
    }
  }
}

String safeDecodeBase64(String str) {
  try {
    return utf8.decode(base64Decode(str));
  } catch (e) {
    return str;
  }
}
