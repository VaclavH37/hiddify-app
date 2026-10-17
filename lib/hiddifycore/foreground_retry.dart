import 'dart:async';

import 'package:grpc/grpc.dart';

/// Thrown by [callForegroundCore] when the foreground core is still unreachable
/// after one heal.
class ForegroundCoreUnreachable implements Exception {
  const ForegroundCoreUnreachable(this.lastError, this.healError);

  /// What the retried call failed with.
  final Object lastError;

  /// Why the heal itself failed, or null if it reported success. Preferred in
  /// messages when present: it says WHY the core is not there, where
  /// [lastError] only says that it is not.
  final String? healError;

  @override
  String toString() => 'ForegroundCoreUnreachable($lastError, heal: ${healError ?? "ok"})';
}

/// Whether [error] means nothing answered on the foreground core's port.
///
/// `UNAVAILABLE` is what a refused connection, or a certificate the pin
/// rejects, looks like through gRPC. Anything that is not a gRPC error at all
/// counts too: the client may never have been built, because the setup that
/// builds it failed (`LateInitializationError`). Other gRPC codes mean the core
/// answered, and restarting it would not change the answer.
bool isForegroundUnreachable(Object error) => error is! GrpcError || error.code == StatusCode.unavailable;

/// Runs [call] against the foreground core, and if the core is unreachable,
/// runs [heal] once and calls again.
///
/// The foreground core can stop listening while the app is suspended: iOS may
/// reclaim the resources under a suspended app's sockets. Without a retry the
/// next profile import failed with "cannot reach the local core" until the app
/// was force-quit.
///
/// [call] must read the client afresh each time it runs, because [heal]
/// replaces it. [heal] returns null on success or the reason it failed.
///
/// [shouldHeal] decides which errors are worth a heal; errors it rejects are
/// rethrown untouched. If the second attempt also fails with one it accepts,
/// this throws [ForegroundCoreUnreachable].
Future<T> callForegroundCore<T>({
  required Future<T> Function() call,
  required Future<String?> Function(Object error) heal,
  bool Function(Object error) shouldHeal = isForegroundUnreachable,
}) async {
  try {
    return await call();
  } catch (first) {
    if (!shouldHeal(first)) rethrow;
    final healError = await heal(first);
    try {
      return await call();
    } catch (second) {
      if (!shouldHeal(second)) rethrow;
      throw ForegroundCoreUnreachable(second, healError);
    }
  }
}

/// Runs at most one [run] task at a time; callers that arrive while one is in
/// flight share its result. The next call after it settles starts a new one.
class SingleFlight<T> {
  Future<T>? _running;

  Future<T> run(Future<T> Function() task) => _running ??= task().whenComplete(() => _running = null);
}
