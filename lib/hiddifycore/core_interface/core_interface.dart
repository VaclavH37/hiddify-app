import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';

/// The header carrying the shared secret the core requires on every call
/// (requireSecret in grpc_server.go). It must stay lower-case: gRPC normalises
/// header names and rejects a key containing upper case outright. Asserted
/// core-side too (TestSecretMetadataKeyIsWireLegal).
const grpcSecretMetadataKey = 'x-rayn-secret';

class CoreInterface {
  late CoreClient fgClient;
  late CoreClient bgClient;

  Future<String> setup(Directories directories, bool debug, int mode) async {
    return "";
  }

  Future<CoreStatus> setupBackground(String path, String name) async {
    return const CoreStarted();
  }

  Future<bool> restart(String path, String name) async {
    return false;
  }

  Future<bool> stop() async {
    return false;
  }

  Future<bool> isBgClientAvailable() async {
    return true;
  }

  bool isSingleChannel() {
    // return true;
    return fgClient == bgClient;
  }

  /// Whether both channels reach cores in one process, which then publish one
  /// log to both (see skipsLogListener).
  bool get coreSharesProcess => false;

  Future<bool> resetTunnel() async {
    return false;
  }

  Future<bool> isActiveFg() async {
    return true;
  }

  Future<bool> isActiveBg() async {
    return true;
  }

  /// The password the core's local mixed port asks for (local_proxy_auth.dart),
  /// or null when it asks for none. Read on every connection to that port: on
  /// mobile the secret it is derived from rotates with each connect.
  String? get localProxyPassword => null;

  /// Runs [body] with the app kept alive until it finishes, where the platform
  /// would suspend it part-way. A pass-through wherever the app keeps running
  /// in the background.
  Future<T> withBackgroundTime<T>(Future<T> Function() body) => body();

  bool isInitialized() {
    try {
      // Reading a `late` field that was never set throws; that is the test.
      // ignore: unnecessary_statements
      bgClient;
      return true;
    } catch (_) {
      return false;
    }
  }
}
