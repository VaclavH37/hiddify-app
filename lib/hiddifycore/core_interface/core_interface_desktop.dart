import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/gen/hiddify_core_generated_bindings.dart';
import 'package:hiddify/hiddifycore/core_interface/core_certificate_pin.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/core_interface/local_proxy_auth.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/utils/custom_loggers.dart';

import 'package:loggy/loggy.dart';

import 'package:path/path.dart' as p;

final _logger = Loggy('HiddifyCoreFFI');
typedef StopFunc = Pointer<Utf8> Function();
typedef StopFuncDart = Pointer<Utf8> Function();

class CoreInterfaceDesktop extends CoreInterface with InfraLogger {
  /// The core library itself, opened once. Exposed for the few exports that
  /// are called directly rather than over gRPC (see `egress_routing_probe.dart`);
  /// opening it from a second place would duplicate the path logic below.
  static final DynamicLibrary library = _open();

  static final HiddifyCoreNativeLibrary _box = HiddifyCoreNativeLibrary(library);

  static DynamicLibrary _open() {
    String fullPath = "";
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      fullPath = "hiddify-core";
    }
    if (Platform.isWindows) {
      // Rayn rebrand: the Windows core ships as rayn-core.dll (see the
      // windows-amd64 target in hiddify-core/Makefile + windows/CMakeLists.txt).
      // macOS/Linux still use the hiddify-core name.
      fullPath = p.join(fullPath, "rayn-core.dll");
    } else if (Platform.isMacOS) {
      fullPath = p.join(fullPath, "hiddify-core.dylib");
    } else {
      fullPath = p.join(fullPath, "hiddify-core.so");
    }

    _logger.debug('hiddify-core native libs path: "$fullPath"');
    // final stopFunc = lib.lookup<NativeFunction<StopFunc>>('stop').asFunction<StopFunc>();
    // final errPtr2 = stopFunc();
    // final err = errPtr2.cast<Utf8>().toDartString();

    return DynamicLibrary.open(fullPath);
  }

  Future<bool> isMusl() async {
    try {
      final result = await Process.run('ldd', ['--version']);
      return result.stdout.toString().toLowerCase().contains('musl');
    } catch (_) {
      return false;
    }
  }

  // Same collision as mobile — a desktop Hiddify install binds this too, and
  // loopback is not isolated between processes on any desktop OS either. Kept in
  // step with CoreInterfaceMobile.portFront; see the reasoning there.
  final port = 21978;

  /// [length] characters from a CSPRNG. Letters and digits only: the value
  /// crosses FFI as a C string and travels as an HTTP/2 header.
  static String generateRandomPassword(int length) {
    const characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => characters[random.nextInt(characters.length)]).join();
  }

  /// The credential the core requires on every call (requireSecret,
  /// grpc_server.go). New for each process, never stored.
  static final String secret = generateRandomPassword(100);

  /// From [secret]: on desktop the core in this process runs the tunnel.
  @override
  String? get localProxyPassword => deriveLocalProxyPassword(secret);

  // The channel behind fgClient and bgClient, kept so a later setup can shut it
  // down rather than leave it connected until its idle timeout.
  ClientChannel? _channel;

  @override
  Future<String> setup(Directories directories, bool debug, int mode) async {
    // Authenticated in both directions, as on mobile (mode 1, GRPC_NORMAL): TLS
    // with a certificate this client pins, and a secret the core requires on
    // every call. This used to be mode 3, plaintext with no authentication, so
    // any program on the machine could drive the core, which runs elevated here:
    // start or stop the tunnel, or read every hub and node address from
    // OutboundsInfo. Mode 3 itself stays for the standalone CLI, on its own port.
    //
    // No unauthenticated hello probe first any more; it would attach to
    // whatever answered on the port. hcore.Setup returns early when this mode's
    // server already exists, so calling it every time is safe.
    //
    // Debug builds: a hot restart mints a new secret while the running core
    // keeps the first one, so every call is refused until the app is restarted.
    final err = using((arena) {
      final errPtr = _box.setup(
        directories.baseDir.path.toNativeUtf8(allocator: arena).cast(),
        directories.workingDir.path.toNativeUtf8(allocator: arena).cast(),
        directories.tempDir.path.toNativeUtf8(allocator: arena).cast(),
        SetupMode.GRPC_NORMAL.value,
        "127.0.0.1:$port".toNativeUtf8(allocator: arena).cast(),
        secret.toNativeUtf8(allocator: arena).cast(),
        0,
        debug ? 1 : 0,
      );
      // Read at once and not freed. The core hands the string over (since
      // hiddify-core 74afa56; it used to free an error string before returning
      // it), but a DLL from before that has already freed it, so freeing here
      // could double-free. setup runs once per launch; the few bytes stay.
      return errPtr.cast<Utf8>().toDartString();
    });
    if (err.isNotEmpty) {
      return err;
    }

    // In-process, over FFI: fetching the certificate over the connection it is
    // meant to authenticate would authenticate nothing.
    final keyPtr = _box.GetServerPublicKey();
    final pem = keyPtr.cast<Utf8>().toDartString();
    _box.freeString(keyPtr);
    if (pem.isEmpty) {
      // Fail rather than fall back to an insecure channel: a silent downgrade is
      // the one outcome worse than not connecting.
      return "core did not provide a certificate to pin";
    }
    final pin = CoreCertificatePin.fromPem(Uint8List.fromList(utf8.encode(pem)));
    if (pin == null) {
      return "core certificate is not a valid PEM";
    }

    final replaced = _channel;
    _channel = ClientChannel(
      '127.0.0.1',
      port: port,
      options: ChannelOptions(credentials: pin.credentials()),
    );
    // On the client rather than per call, so no RPC can be added without it.
    bgClient = fgClient = CoreClient(_channel!, options: CallOptions(metadata: {grpcSecretMetadataKey: secret}));
    // Never awaited: grpc's shutdown waits for the streams still open on it.
    replaced?.shutdown().ignore();

    return "";
  }

  @override
  Future<bool> restart(String path, String name) async {
    return false;
  }

  @override
  Future<bool> stop() async {
    return false;
  }
}
