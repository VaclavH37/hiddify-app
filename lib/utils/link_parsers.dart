import 'dart:convert';

import 'package:hiddify/utils/rayn_token.dart';

typedef ProfileLink = ({String url, String name});

abstract class LinkParser {
  // Only the rayn:// scheme is accepted. All other deep-link schemes and
  // bare https URLs are rejected — subscriptions must arrive as a backend-
  // issued `rayn://import/<encrypted_token>` link.
  static const protocols = ['rayn'];

  static ProfileLink? parse(String link) => deep(link);

  static ProfileLink? deep(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    if (uri.scheme != 'rayn') return null;
    // Format: rayn://import/<base64url_token>
    // The token MUST live in the path, not the authority — Dart's
    // `Uri.host` is normalized to lowercase, which corrupts the
    // case-sensitive base64url payload. The path component preserves case.
    if (uri.host != 'import') return null;
    final encoded = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    if (encoded.isEmpty) return null;
    final decrypted = RaynTokenDecryptor.decryptToUrl(encoded);
    if (decrypted == null) return null;
    return (url: decrypted, name: '');
  }
}

String safeDecodeBase64(String str) {
  try {
    return utf8.decode(base64Decode(str));
  } catch (e) {
    return str;
  }
}
