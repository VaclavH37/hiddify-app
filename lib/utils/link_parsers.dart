import 'dart:convert';

import 'package:hiddify/utils/rayn_token.dart';

abstract class LinkParser {
  // Only the rayn:// scheme is accepted. All other deep-link schemes and
  // bare https URLs are rejected — subscriptions must arrive as a backend-
  // issued `rayn://import/<encrypted_token>` link.
  static const protocols = ['rayn'];

  /// Parses and decrypts a `rayn://import/<token>` cryptolink.
  ///
  /// Returns a three-way result, not a nullable: "this build is too old to read
  /// this link" and "this link is broken" need different words in front of the
  /// user, and callers that collapse them produce actively misleading messages
  /// (RAYN-LINK-SYMMETRIC-MIGRATION.md §10).
  static RaynLinkResult parse(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return const RaynLinkInvalid(RaynLinkRejection.notARaynLink);
    }
    // Format: rayn://import/<base64url_token>
    // The token MUST live in the path, not the authority — Dart's
    // `Uri.host` is normalized to lowercase, which corrupts the
    // case-sensitive base64url payload. The path component preserves case.
    if (uri.scheme != 'rayn' || uri.host != 'import') {
      return const RaynLinkInvalid(RaynLinkRejection.notARaynLink);
    }
    final encoded = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    if (encoded.isEmpty) return const RaynLinkInvalid(RaynLinkRejection.empty);
    return RaynTokenDecryptor.decrypt(encoded);
  }
}

String safeDecodeBase64(String str) {
  try {
    return utf8.decode(base64Decode(str));
  } catch (e) {
    return str;
  }
}
