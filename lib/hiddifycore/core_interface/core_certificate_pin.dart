import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:grpc/grpc.dart';
import 'package:loggy/loggy.dart';

/// The core's gRPC server certificate, pinned by its exact bytes.
///
/// The core mints a fresh self-signed certificate at every setup and hands it
/// to the app in-process: over the method channel on mobile, through an FFI
/// export on desktop. Fetching it over the connection it is meant to
/// authenticate would authenticate nothing. The channel then accepts that
/// certificate and nothing else.
///
/// [credentials] sets the pin both ways, and both are needed:
/// - `certificates:` builds a SecurityContext that trusts only these bytes, so a
///   handshake with any other core aborts instead of succeeding.
/// - `onBadCertificate` is not a relaxation of that. It is the same pin enforced
///   a second way, by byte equality, and on iOS it is the ONLY way that works:
///   Security.framework applies Apple's TLS server policy on top of chain
///   validity, and rejected this certificate with `CERTIFICATE_VERIFY_FAILED:
///   application verification failure` while the bytes on both ends were
///   identical. Equality is strictly narrower than anchor trust, since an anchor
///   would also vouch for anything it signed, so nothing is accepted that the
///   trust-store path would have refused.
///
/// Do not remove either half as redundant.
class CoreCertificatePin {
  CoreCertificatePin._(this.pem, this._der);

  /// The pin for [pem], or null when it is not a PEM certificate.
  static CoreCertificatePin? fromPem(Uint8List pem) {
    final der = _derFromPem(pem);
    return der == null ? null : CoreCertificatePin._(pem, der);
  }

  static final _log = Loggy('CoreCertificatePin');

  /// The certificate exactly as the core handed it over.
  final Uint8List pem;

  /// [pem] decoded once, so the pin check is a byte comparison rather than a
  /// parse on every handshake.
  final Uint8List _der;

  /// True only when [certificate] is byte for byte the pinned one. The
  /// comparison does not stop at the first differing byte.
  bool matches(X509Certificate certificate) {
    final presented = certificate.der;
    if (presented.length != _der.length) {
      _log.error("core certificate does not match the pin; refusing the channel");
      return false;
    }
    var difference = 0;
    for (var i = 0; i < _der.length; i++) {
      difference |= _der[i] ^ presented[i];
    }
    if (difference != 0) {
      _log.error("core certificate does not match the pin; refusing the channel");
      return false;
    }
    return true;
  }

  /// TLS credentials that accept this certificate and nothing else.
  ChannelCredentials credentials() => ChannelCredentials.secure(
    certificates: pem,
    onBadCertificate: (certificate, _) => matches(certificate),
  );

  static Uint8List? _derFromPem(Uint8List pem) {
    final body = String.fromCharCodes(
      pem,
    ).replaceAll(RegExp('-----[^-]+-----'), '').replaceAll(RegExp(r'\s'), '');
    if (body.isEmpty) return null;
    try {
      return base64.decode(body);
    } on FormatException {
      return null;
    }
  }
}
