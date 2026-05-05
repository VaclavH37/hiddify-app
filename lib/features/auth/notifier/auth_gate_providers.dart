import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Holds a `rayn://import/<token>` URL captured at cold start so the
/// `AuthPage` can auto-import as soon as it mounts. Cleared after
/// consumption to avoid double-imports on re-entrant redirects.
final pendingDeepLinkUrlProvider = StateProvider<String?>((ref) => null);
