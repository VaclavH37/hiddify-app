import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/singbox/model/core_status.dart';

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

  Future<bool> resetTunnel() async {
    return false;
  }

  Future<bool> isActiveFg() async {
    return true;
  }

  Future<bool> isActiveBg() async {
    return true;
  }

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
