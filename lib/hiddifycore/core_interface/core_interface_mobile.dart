import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/utils/laststeam.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';

import 'package:hiddify/utils/utils.dart';
import 'package:loggy/loggy.dart';
import 'package:rxdart/rxdart.dart';

final _logger = Loggy('FFIRaynCoreService');

class CoreInterfaceMobile extends CoreInterface with InfraLogger {
  static const channelPrefix = "com.raynlabs.app";
  static const methodChannel = MethodChannel("$channelPrefix/method");
  static const statusChannel = EventChannel("$channelPrefix/service.status", JSONMethodCodec());
  static const alertsChannel = EventChannel("$channelPrefix/service.alerts", JSONMethodCodec());

  // Was `late Uint8List serverPublicKey` plus a generated EC key pair for a
  // client certificate. The client-certificate half is gone: the core rejected
  // certificates outright and, for a public key, built an x509.Certificate with
  // no Raw, Subject or signature — nothing can chain to that, so the mTLS mode
  // could never have completed a handshake. The client authenticates with a
  // shared secret instead; TLS is here for the half only it can do, which is
  // letting us pin the server.
  //
  // Both are fetched over the METHOD CHANNEL, which is in-process and therefore
  // trustworthy. Fetching either over the connection they are meant to
  // authenticate would authenticate nothing.
  Uint8List? _serverCertificate;

  /// DER of [_serverCertificate], decoded once so the pin check is a byte
  /// comparison rather than a parse on every handshake.
  Uint8List? _pinnedDer;
  String? _secret;

  // Loopback gRPC ports for the two cores: `portFront` is the one embedded in
  // this app process, `portBack` the one in the platform VPN service.
  //
  // MOVED OFF UPSTREAM'S 17078/17079, and that is the whole point. iOS and
  // Android both share the loopback interface between apps, so whichever process
  // binds first owns the port and the other app's client silently attaches to it.
  // With Hiddify installed alongside, that is not hypothetical: a `rayn://`
  // import succeeded by having *Hiddify's* core parse our decrypted subscription
  // — hub address, per-user UUIDs and Reality shortIDs — over an unauthenticated
  // socket. Any Hiddify-derived client collides the same way.
  //
  // Distinct ports remove the collision but not the exposure — a fixed port is
  // still squattable by anything that starts first. The channel is now
  // authenticated in both directions (mode 1): TLS with a certificate this
  // client pins, and a per-install secret the core requires on every call. The
  // ports matter for the ordinary case; the credentials matter for the hostile
  // one.
  //
  // Chosen below the ephemeral range (49152+) so the OS cannot assign them to
  // something else, above 1024, and clear of the common development ports. Keep
  // these in step with ExtensionProvider.swift and Settings.kt — the app supplies
  // the port and the native values are fallbacks, so a mismatch surfaces only on
  // an on-demand start, with the app closed.
  static const portBack = 21979;
  static const portFront = 21978;

  bool _isBgClientAvailable = false;
  bool _debug = false;

  late LastStream<CoreStatus> _status;
  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    _debug = debug;
    final secureMode = [1, 2].contains(mode);

    final status = statusChannel.receiveBroadcastStream().map(CoreStatus.fromEvent);
    final alerts = alertsChannel.receiveBroadcastStream().map(CoreStatus.fromEvent);
    _status = LastStream(ValueConnectableStream(Rx.merge([status, alerts])).autoConnect());

    // Set the core up FIRST, unconditionally.
    //
    // This used to probe with sayHello and only call `setup` if the probe threw,
    // which cannot work for a secure mode: the credentials needed to make that
    // probe are produced BY the setup it is trying to avoid. It was also the
    // shape behind the iOS import failure — a probe that failed while the server
    // was up drove a retry into a refusal it could never clear.
    //
    // Calling it every time is safe: hcore.Setup returns early when a server for
    // the mode already exists (grpc_server.go), so this is a no-op on the second
    // and later calls.
    await methodChannel.invokeMethod("setup", {
      "baseDir": directories.baseDir.path,
      "workingDir": directories.workingDir.path,
      "tempDir": directories.tempDir.path,
      "grpcPort": portFront,
      "mode": mode,
      "debug": debug,
    });

    ChannelCredentials channelOption = const ChannelCredentials.insecure();
    if (secureMode) {
      // Both over the method channel, in this order: the certificate does not
      // exist until the core has been set up.
      _serverCertificate = await methodChannel.invokeMethod<Uint8List>("get_grpc_server_public_key");
      _secret = await methodChannel.invokeMethod<String>("get_grpc_secret");

      if (_serverCertificate == null || _serverCertificate!.isEmpty) {
        return "core did not provide a certificate to pin";
      }
      if (_secret == null || _secret!.isEmpty) {
        // Fail rather than fall back to an insecure channel. A silent downgrade
        // is the one outcome worse than not connecting, because everything keeps
        // working and nothing says the channel is open to any local process.
        return "core did not provide a credential";
      }

      _pinnedDer = _derFromPem(_serverCertificate!);
      if (_pinnedDer == null) {
        return "core certificate is not a valid PEM";
      }

      // Pins the certificate and nothing else — ChannelCredentials.secure builds
      // a SecurityContext with no trusted roots and adds only these bytes, so a
      // handshake with any other core aborts instead of succeeding.
      //
      // `onBadCertificate` is not a relaxation of that, it is the same pin
      // enforced a second way, and on iOS it is the ONLY way that works.
      // `certificates:` asks the platform's trust engine to chain the peer to
      // this certificate as an anchor, and on Apple platforms that engine is
      // Security.framework, not BoringSSL — it applies Apple's own TLS server
      // policy on top of chain validity, and it rejected this certificate with
      // `CERTIFICATE_VERIFY_FAILED: application verification failure` while the
      // bytes on both ends were identical. (A real mismatch reports
      // `self signed certificate`; the two are distinguishable, which is how
      // this was told apart from a plumbing bug.)
      //
      // Chain validation was never what this needed. The question here is not
      // "does this certificate chain to something I trust" but "is this the
      // exact certificate the core handed me in-process moments ago", and an
      // equality check answers that directly — strictly narrower than anchor
      // trust, since an anchor would also vouch for anything it signed. Nothing
      // is accepted that the trust-store path would have refused.
      channelOption = ChannelCredentials.secure(
        certificates: _serverCertificate,
        onBadCertificate: _isPinnedCertificate,
      );
      await _reportPinnedCertificate(channelOption);
    }

    fgClient = CoreClient(
      ClientChannel(
        '127.0.0.1',
        port: portFront,
        options: ChannelOptions(credentials: channelOption),
      ),
      options: _callOptions(),
    );

    // INSECURE, deliberately, and it must stay that way until the background core
    // can present the same certificate this client pinned.
    //
    // The background core runs in the platform VPN service — a separate process,
    // started as mode 4 (GRPC_BACKGROUND_INSECURE) in BoxService.kt and
    // ExtensionProvider.swift. Giving this client the foreground credentials made
    // it speak TLS to a plaintext server, so the handshake failed and the tunnel
    // could not start at all.
    //
    // Raising that core to mode 2 is not a one-line change either: the server
    // certificate is persisted in the core's LevelDB (grpc_server_private_key),
    // and goleveldb takes a single-process file lock. The service cannot read the
    // store the app process holds, so it would generate a DIFFERENT certificate
    // and fail the pin anyway. Securing this channel means distributing the
    // certificate the way GrpcSecret distributes the secret — keychain on iOS,
    // SharedPreferences on Android — which is its own change.
    //
    // NO SECRET ON THIS CHANNEL. Sending it over a plaintext loopback socket
    // would hand it to any local process listening, which is exactly what the
    // foreground channel exists to prevent.
    bgClient = CoreClient(
      ClientChannel(
        '127.0.0.1',
        port: portBack,
        options: const ChannelOptions(credentials: ChannelCredentials.insecure()),
      ),
    );
    // await start("/sdcard/Android/data/com.raynlabs.app/files/configs/cdc633e9-8cfc-4a67-948d-009f779a5c91.json", "hiddify");
    return "";
  }

  /// The pin, enforced directly: true only when the peer presents byte-for-byte
  /// the certificate this client fetched from the core over the method channel.
  ///
  /// Reached only after the platform's own verification has already failed, so
  /// returning false here leaves the handshake exactly as it would have been.
  /// Returning true accepts one specific certificate and no other — not a class
  /// of certificates, not anything a CA signed, and not the peer's word for its
  /// own hostname. Possessing the certificate is not enough to use it either:
  /// the handshake still requires the matching private key, which never leaves
  /// the core.
  bool _isPinnedCertificate(X509Certificate certificate, String host) {
    final pinned = _pinnedDer;
    if (pinned == null) return false;

    final presented = certificate.der;
    if (presented.length != pinned.length) {
      loggy.error("core certificate does not match the pin; refusing the channel");
      return false;
    }
    var difference = 0;
    for (var i = 0; i < pinned.length; i++) {
      difference |= pinned[i] ^ presented[i];
    }
    if (difference != 0) {
      loggy.error("core certificate does not match the pin; refusing the channel");
      return false;
    }
    return true;
  }

  /// Decodes a PEM certificate to DER, or null if it is not one.
  static Uint8List? _derFromPem(Uint8List pem) {
    final body =
        String.fromCharCodes(pem).replaceAll(RegExp('-----[^-]+-----'), '').replaceAll(RegExp(r'\s'), '');
    if (body.isEmpty) return null;
    try {
      return base64.decode(body);
    } on FormatException {
      return null;
    }
  }

  /// Compares the certificate this client pinned against the one the core
  /// actually presents, and says which of the two is wrong.
  ///
  /// Diagnostics builds only — it opens a second TLS connection purely to look
  /// at the peer certificate, which a shipped build has no reason to do.
  ///
  /// It exists because a pinning failure reports nothing useful on its own: the
  /// core generates the certificate and hands it to this client over the method
  /// channel in the same process, so `CERTIFICATE_VERIFY_FAILED` says only that
  /// the two disagree, not which one is unexpected. `onBadCertificate` fires
  /// after built-in verification has already failed, so reaching it at all
  /// answers half the question, and the peer certificate it carries answers the
  /// rest — a subject other than `CN=rayn-core` means something else holds the
  /// port, and a matching subject with a different fingerprint means the core
  /// regenerated after this client fetched.
  ///
  /// Logs a fingerprint and the certificate's public fields, never key
  /// material: the private half never leaves the core.
  Future<void> _reportPinnedCertificate(ChannelCredentials credentials) async {
    if (!Constants.diagnosticsBuild) return;
    final pinned = _serverCertificate;
    if (pinned == null) return;

    // offsetInBytes / buffer length are here because platform channels hand
    // back a Uint8List VIEW onto the message buffer rather than a standalone
    // list, and an API that reads through `.buffer` would see the whole message
    // instead of the certificate.
    loggy.info(
      'pinned certificate: ${_pemFingerprint(String.fromCharCodes(pinned))} len=${pinned.length} '
      'offset=${pinned.offsetInBytes} buffer=${pinned.buffer.lengthInBytes} '
      'header="${String.fromCharCodes(pinned.take(27).toList())}"',
    );

    try {
      final probe = await SecureSocket.connect(
        '127.0.0.1',
        portFront,
        context: credentials.securityContext,
        timeout: const Duration(seconds: 5),
        onBadCertificate: (certificate) {
          loggy.warning(
            'platform trust REJECTED the core certificate '
            '(pin match: ${_isPinnedCertificate(certificate, "127.0.0.1")}): '
            '${_pemFingerprint(certificate.pem)} '
            'subject=${certificate.subject.trim()} issuer=${certificate.issuer.trim()} '
            'from=${certificate.startValidity.toIso8601String()} '
            'to=${certificate.endValidity.toIso8601String()}',
          );
          return _isPinnedCertificate(certificate, '127.0.0.1');
        },
      );
      loggy.info('core certificate accepted');
      await probe.close();
    } catch (e) {
      loggy.warning('certificate probe failed: $e');
    }
  }

  /// SHA-256 over a PEM's base64 body, ignoring armour and line breaks, so a
  /// certificate hashes the same whether Go or Dart re-encoded it.
  static String _pemFingerprint(String pem) {
    final body = pem.replaceAll(RegExp('-----[^-]+-----'), '').replaceAll(RegExp(r'\s'), '');
    if (body.isEmpty) return 'sha256=<not a PEM>';
    return 'sha256=${sha256.convert(body.codeUnits).toString().substring(0, 16)}';
  }

  /// Call metadata carrying the shared secret, or none in an insecure mode.
  ///
  /// Set on the CLIENT rather than per call, so a future RPC cannot be added
  /// without it — the core rejects an unauthenticated call, so forgetting one
  /// would fail closed, but it would fail at runtime on a device rather than
  /// here.
  ///
  /// The key must stay lower-case: gRPC normalises header names and rejects a
  /// key containing upper case outright. It is asserted core-side too
  /// (TestSecretMetadataKeyIsWireLegal).
  CallOptions _callOptions() {
    final secret = _secret;
    if (secret == null || secret.isEmpty) return CallOptions();
    return CallOptions(metadata: {'x-rayn-secret': secret});
  }

  @override
  Future<CoreStatus> setupBackground(String path, String name) async {
    // if (!await waitUntilPort(portBack, false, stop)) return const CoreStatus.stopped(alert: CoreAlert.createService);
    if (!await stop()) return const CoreStatus.stopped(alert: CoreAlert.createService);
    _status.clean();
    await methodChannel.invokeMethod("start", {
      "path": path,
      "name": name,
      "grpcPort": portBack,
      "startBg": true,
      "debug": _debug,
    });

    _isBgClientAvailable = true;
    loggy.info("Waiting for starting core");
    for (var i = 0; i < 20; i++) {
      try {
        final res = await _status.get(timeout: const Duration(seconds: 1));

        switch (res) {
          case CoreStarted():
            break;
          case CoreStopped():
            if (res.alert != null) {
              return res;
            }

          case CoreStopping():
          // return res;
          case CoreStarting():
        }
        await Future.delayed(const Duration(milliseconds: 200));
      } on TimeoutException {
        // just retry
      }
    }
    loggy.info("Waiting for starting core finished");

    if (!await waitUntilPort(portBack, true, null, maxTry: 10)) {
      await stopMethodChannel();
      return const CoreStatus.stopped(alert: CoreAlert.startService, message: "starting background core...");
    }
    return const CoreStarted();
  }

  @override
  Future<bool> stop() async {
    await stopMethodChannel();
    if (!await waitUntilPort(portBack, false, null, maxTry: 10)) {
      return false;
    }

    _isBgClientAvailable = false;
    return true;
  }

  Future stopMethodChannel() async {
    await methodChannel.invokeMethod("stop");
  }

  @override
  Future<bool> isBgClientAvailable() async {
    return _isBgClientAvailable;
  }

  @override
  Future<bool> resetTunnel() async {
    await methodChannel.invokeMethod("reset");
    return true;
  }

  @override
  Future<bool> isActiveFg() async {
    return await isPortOpen("127.0.0.1", portFront);
  }

  @override
  Future<bool> isActiveBg() async {
    return await isPortOpen("127.0.0.1", portBack);
  }
}

Future<bool> waitUntilPort(
  int portNumber,
  bool isOpen,
  Future Function()? callFunctionAfterEachFail, {
  int maxTry = 10,
}) async {
  for (var i = 0; i < maxTry; i++) {
    if (await isPortOpen("127.0.0.1", portNumber) == isOpen) {
      return true;
    }
    if (callFunctionAfterEachFail != null) {
      await callFunctionAfterEachFail();
    }

    await Future.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

Future<bool> isPortOpen(String host, int port, {Duration timeout = const Duration(milliseconds: 300)}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    await socket.close();
    return true;
  } on SocketException catch (_) {
    return false;
  } catch (_) {
    return false;
  }
}
