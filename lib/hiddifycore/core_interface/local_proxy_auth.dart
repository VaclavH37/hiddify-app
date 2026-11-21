import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The core's local mixed port (127.0.0.1:12334) asks for a password while it
/// runs, because loopback is shared by every app on the device. The app's own
/// tunnel-only fetches go through that port (rule-set and app updates, the
/// middleware probes), so [DioHttpClient] sends it.
///
/// Both sides derive the password from the gRPC secret they already share, so
/// nothing new is stored or sent: the secret of the core that runs the tunnel,
/// which is the background core's on Android and iOS and the foreground core's
/// on desktop (see each [CoreInterface.localProxyPassword]). The core's half is
/// `hiddify-core/v2/config/local_proxy_auth.go` and `v2/hcore/local_proxy_auth.go`;
/// both halves pin the same test vector, and if they ever disagree every
/// tunnel-only fetch is refused with a 407.
const localProxyUser = 'rayn';

const _localProxyLabel = 'rayn-local-proxy';

/// HMAC-SHA256 keyed with [secret] over "rayn-local-proxy", as lower-case hex;
/// null for no secret, which is what a core set up without one expects.
String? deriveLocalProxyPassword(String? secret) {
  if (secret == null || secret.isEmpty) return null;
  return Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(_localProxyLabel)).toString();
}
