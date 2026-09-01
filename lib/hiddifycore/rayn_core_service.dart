import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/warp_account.dart';

import 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper_stub.dart'
    if (dart.library.io) 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart' as loggyl;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';

class RaynCoreService with InfraLogger {
  RaynCoreService(this.ref);
  final Ref ref;

  // CoreRaynCoreService() {}
  final core = getCoreInterface();

  CoreStatus currentState = const CoreStatus.stopped();
  final statusController = BehaviorSubject<CoreStatus>();
  final logController = BehaviorSubject<List<LogMessage>>();
  final CallOptions? grpcOptions = null; //CallOptions(timeout: const Duration(milliseconds: 10000));
  final Map<String, StreamSubscription?> subscriptions = {};
  List<OutboundGroup> latest = [];

  Future<void> init() async {
    await setup()
        .mapLeft((e) {
          loggy.error(e);
          if (PlatformUtils.isIOS) return;
          statusController.add(const CoreStatus.stopped());
          ref.read(inAppNotificationControllerProvider).showErrorToast(e);
        })
        .map((_) {
          loggy.info("core setup done");
          ref.read(coreRestartSignalProvider.notifier).restart();
        })
        .run();
  }

  /// Validates a raw subscription body and returns the normalised sing-box JSON.
  ///
  /// Deliberately passes only `content` and leaves both path fields empty: the
  /// core writes a file if and only if `configPath` is set (see
  /// `v2/hcore/buildconfighelper.go`), so this is what keeps the plaintext
  /// config off disk. The caller seals the returned JSON into
  /// `configs/<id>.enc` instead.
  TaskEither<String, String> validateConfig(String content) {
    return TaskEither(() async {
      ParseResponse response;
      try {
        response = await core.fgClient.parse(ParseRequest(content: content, debug: false));
      } catch (first) {
        // The foreground core is unreachable. Re-running setup is worth one
        // attempt, but the retry has to be caught too: it used to be bare, so a
        // second failure escaped this TaskEither entirely and reached the caller
        // as a raw exception. That is how "the core is not listening" reached
        // the user as `Failed to add profile: Unexpected error Error connecting:
        // SocketException ... port 49465` — an ephemeral LOCAL port, which
        // reads like a network fault and names nothing that exists in this
        // codebase. The real destination is the foreground core on 127.0.0.1.
        loggy.warning("foreground core unreachable during parse, re-running setup", first);
        final setupResult = await setup().run();
        final setupError = setupResult.getLeft().toNullable();
        try {
          response = await core.fgClient.parse(ParseRequest(content: content, debug: false));
        } catch (second) {
          // Prefer setup's own message: it says WHY the core did not come up,
          // where the parse failure only says that it is absent. Discarding it
          // was the other half of the same bug.
          return left(
            setupError != null
                ? "core did not start: $setupError"
                : "cannot reach the local core to validate the configuration: $second",
          );
        }
      }
      if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      return right(response.content);
    });
  }

  TaskEither<String, String> generateFullConfig(String content) {
    return TaskEither(() async {
      final response = await core.fgClient.parse(ParseRequest(content: content, debug: false));
      if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      return right(response.content);
    });
  }

  TaskEither<String, Unit> setup() {
    return TaskEither(() async {
      try {
        final directories = ref.read(appDirectoriesProvider).requireValue;
        // Feeds SetupRequest.Debug -> static.debug in the core.
        //
        // The kDebugMode branch is load-bearing, not belt-and-braces: the Debug
        // mode tile is compiled out of release builds, but the preference behind
        // it is persisted — so an install that enabled it before upgrading would
        // otherwise keep sending `true` forever with no UI left to turn it off.
        //
        // A release build therefore ignores the preference entirely and asks
        // instead whether this is a diagnostics build, which is a compile-time
        // decision nothing on the device can flip.
        final debug = kDebugMode ? ref.read(debugModeNotifierProvider) : Constants.diagnosticsBuild;
        // Mode 1 = GRPC_NORMAL: TLS with a certificate this client pins, plus the
        // per-install secret on every call. Was 3, GRPC_NORMAL_INSECURE — a plain
        // channel on a loopback port that is not isolated between apps, which is
        // how a rayn:// import came to be served by Hiddify's core, decrypted
        // subscription and all.
        //
        // Mobile only in practice: CoreInterfaceDesktop hardcodes the insecure
        // mode and ignores this argument until its own path is tested.
        final setupResponse = await core.setup(directories, debug, 1);

        if (setupResponse.isNotEmpty) {
          return left(setupResponse);
        }

        await startListeningLogs("fg", core.fgClient);
        // await startListeningStatus("fg", core.fgClient);
        if (!core.isSingleChannel()) {
          await startListeningLogs("bg", core.bgClient);
        }
        statusController.add(currentState);
        await startListeningStatus("bg", core.bgClient);
        // ref.read(coreRestartSignalProvider.notifier).restart();
        return right(unit);
      } catch (e) {
        return left(e.toString());
      }
    });
  }

  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) {
    return TaskEither(() async {
      loggy.debug("changing options");
      // latestOptions = options;
      final payload = jsonEncode(options.toJson());

      // Deliberately two separate try blocks. They used to share one, and only
      // the background core is allowed to be absent — it lives in the platform
      // VPN service and does not exist until the tunnel starts. Sharing the
      // block meant an unreachable FOREGROUND core hit the same branch and was
      // logged as "background core is not started yet", so the one condition
      // that should stop an import cold was reported as the one that is
      // routine, and the caller carried on into validateConfig to fail there
      // instead.
      try {
        final res = await core.fgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: payload),
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unavailable) {
          loggy.error("foreground core is unreachable", e);
          return left("cannot reach the local core to apply settings: ${e.message ?? e.codeName}");
        }
        rethrow;
      }

      try {
        await core.bgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: payload),
        );
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unavailable) {
          // Expected before the first connect.
          loggy.debug("background core is not started yet! $e");
        } else if (e.code == StatusCode.unauthenticated) {
          // NOT fatal, and it must not become fatal again.
          //
          // This is best-effort propagation to a core that may not be in a usable
          // state yet; the authoritative apply is the FOREGROUND call above.
          // Rethrowing here turned a recoverable credential mismatch into a dead
          // end: the throw happens BEFORE start(), so setupBackground never ran,
          // the background secret was never rotated, and no restart could reach
          // the code that would have fixed it. The only escape was clearing app
          // storage. connect() rotates and re-applies moments later.
          loggy.warning("background core rejected the settings apply, continuing: ${e.message}");
        } else {
          rethrow;
        }
      }

      return right(unit);
    });
  }

  /// Starts the core.
  ///
  /// [sealedPath] is `configs/<id>.enc` and is handed to the platform shell, not
  /// to the core: Android stores it in `Settings.activeConfigPath` and iOS in
  /// `VPNConfig.activeConfigPath`, so that a start the system initiates on its
  /// own — quick-settings tile, always-on, iOS on-demand — can find the file,
  /// decrypt it natively and pass the plaintext to `Mobile.Start`.
  ///
  /// [content] is the already-decrypted sing-box JSON and goes to the core over
  /// gRPC. The core never opens the sealed file itself and never receives the
  /// key.
  TaskEither<ConnectionFailure, Unit> start(
    String sealedPath,
    String content,
    String name,
    bool disableMemoryLimit,
  ) {
    return TaskEither(() async {
      statusController.add(currentState = const CoreStatus.starting());
      loggy.debug("starting");
      final background = await core.setupBackground(sealedPath, name);
      if (background != const CoreStatus.started()) {
        statusController.add(currentState = const CoreStatus.stopped());
        return left(background.getCoreAlert() ?? const ConnectionFailure.unexpected("failed to start core"));
      }
      if (!core.isSingleChannel()) {
        await startListeningLogs("bg", core.bgClient);
        await startListeningStatus("bg", core.bgClient);
      }
      // if (latestOptions != null) {
      //   await core.bgClient.changeHiddifySettings(
      //     ChangeHiddifySettingsRequest(
      //       hiddifySettingsJson: jsonEncode(latestOptions!.toJson()),
      //     ),
      //   );
      // }
      try {
        final res = await core.bgClient.start(
          StartRequest(
            // configContent only — never configPath. `ReadContent` in the core
            // prefers content and only falls back to reading the path, so
            // sending a path here would make the core open a file we have
            // deliberately encrypted.
            configContent: content,
            configName: name,
            disableMemoryLimit: disableMemoryLimit,
          ),
        );
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (res.messageType != MessageType.ALREADY_STARTED && res.messageType != MessageType.EMPTY) {
          final alert = res.message.contains("denied") ? CoreAlert.requestVPNPermission : CoreAlert.startFailed;
          currentState = CoreStatus.stopped(
            alert: alert,
            message: "failed to start core ${res.messageType} ${res.message}",
          );

          statusController.add(currentState);

          return left(
            currentState.getCoreAlert() ??
                ConnectionFailure.unexpected("failed to start core ${res.messageType} ${res.message}"),
          );
        }
      } on GrpcError catch (e) {
        loggy.error("failed to start bg core: $e");
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (e.code == StatusCode.unavailable) {
          return left(const ConnectionFailure.unexpected("background core is not started yet!"));
        }
        // throw InvalidConfig(e.message);
        // throw DioException.connectionError(requestOptions: RequestOptions(), reason: e.codeName, error: e);

        // throw DioException(requestOptions: RequestOptions(), error: e);
        return left(const ConnectionFailure.unexpected("failed to start background core"));
      }

      // if (res.messageType != MessageType.EMPTY) return left(res);

      return right(unit);
    });
  }

  TaskEither<String, Unit> stop() {
    return TaskEither(() async {
      loggy.debug("stopping");
      var errMsg = "";
      try {
        final res = await core.bgClient.stop(Empty());
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2") ?? false)) {
          errMsg = e.message ?? "failed to stop core: $e";

          loggy.error("failed to stop bg core: $e");
        }
      } catch (e) {
        loggy.error("failed to stop bg core: $e");
        // left("failed to stop core: $e");
      }
      if (!await core.stop()) {}
      statusController.add(currentState = const CoreStatus.stopped());
      if (errMsg.isNotEmpty) return left(errMsg);
      return right(unit);
    });
  }

  TaskEither<String, Unit> restart(String content, String name, bool disableMemoryLimit) {
    return TaskEither(() async {
      loggy.debug("restarting");
      // if (!await core.restart(path, name)) {
      try {
        final res = await core.bgClient.restart(
          StartRequest(
            configContent: content,
            configName: name,
            disableMemoryLimit: disableMemoryLimit,
            delayStart: true,
          ),
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
      } on GrpcError catch (e) {
        loggy.error("failed to restart bg core: $e");
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2 error") ?? false)) {
          return left("${e.message}");
        }
      }

      return right(unit);
      // await stop().run();
      // return await start(path, name, disableMemoryLimit).run();
      // }
      // if (!core.isSingleChannel()) {
      //   await startListeningStatus("bg", core.bgClient);
      //   await startListeningLogs("bg", core.bgClient);
      // }
      // return right(unit);
    });
  }

  TaskEither<String, Unit> resetTunnel() {
    return TaskEither(() async {
      // only available on iOS (and macOS later)
      if (!PlatformUtils.isIOS) {
        throw UnimplementedError("reset tunnel function unavailable on platform");
      }

      // loggy.debug("resetting tunnel");
      final res = await core.resetTunnel();
      if (res) {
        return right(unit);
      }
      return left("failed to reset tunnel");
    });
  }

  // Stream<List<OutboundGroup>> watchGroups() async* {
  //   loggy.debug("watching groups");
  //   yield* core.bgClient.outboundsInfo(Empty()).map((event) => event.items);
  //   // res?.cancel();
  // }

  Stream<OutboundGroup?> watchGroup() async* {
    loggy.debug("watching group");
    // interrupt managed by core

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }
    try {
      yield* core.bgClient.outboundsInfo(Empty()).map((event) => event.items.isEmpty ? null : event.items.first);
    } catch (e) {
      loggy.error("error watching group: $e");
      rethrow;
    }
    // //emitting first event immediately
    // yield* core.bgClient.outboundsInfo(Empty()).take(1).map((event) => event.items.isEmpty ? null : event.items.first);
    // //emitting other event after every 4 seconds(latest event)
    // yield* core.bgClient.outboundsInfo(Empty()).throttleTime(const Duration(seconds: 4), leading: false, trailing: true).map((event) => event.items.isEmpty ? null : event.items.first);
  }

  Stream<List<OutboundGroup>> watchActiveGroups() async* {
    loggy.info("watching active groups");

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }

    try {
      yield* core.bgClient
          .mainOutboundsInfo(Empty())
          .map((event) {
            return latest = event.items;
          })
          .startWith(latest);
    } catch (e) {
      loggy.error("error watching active groups: $e");
      rethrow;
    }
  }

  //
  // Stream<SingboxStatus> watchStatus() => _status;

  ResponseStream<SystemInfo> watchStats() {
    loggy.debug("watching stats");
    try {
      return core.bgClient.getSystemInfoStream(Empty());
    } catch (e) {
      loggy.error("error watching stats: $e");
      rethrow;
    }
  }

  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    return TaskEither(() async {
      loggy.debug("selecting outbound");
      try {
        final res = await core.bgClient.selectOutbound(
          SelectOutboundRequest(groupTag: groupTag, outboundTag: outboundTag),
          options: CallOptions(timeout: const Duration(seconds: 1)),
        );
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error selecting outbound: $e");
        rethrow;
      }
    });
  }

  TaskEither<String, Unit> urlTest(String tag) {
    return TaskEither(() async {
      loggy.debug("url test");
      try {
        final res = await core.bgClient.urlTest(UrlTestRequest(tag: tag));
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error in url test: $e");
        rethrow;
      }
    });
  }

  List<LogMessage> logBuffer = [];

  // SingboxConfigOption? latestOptions;

  Stream<List<LogMessage>> watchLogs(String path) async* {
    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty log stream");
      return;
    }
    await startListeningLogs("bg", core.bgClient);
    await startListeningLogs("fg", core.fgClient);
    try {
      yield* logController.stream;
    } catch (e) {
      loggy.error("error watching logs: $e");
      rethrow;
    }
    // Stream<List<String>> logStream(CoreClient coreClient) {
    //   return coreClient.logListener(Empty()).asBroadcastStream().map((event) => [event.message]).onErrorResume((error, stackTrace) {
    //     loggy.debug('Error in $coreClient: $error, retrying...');
    //     final delay = (currentState == const SingboxStatus.stopped()) ? 5 : 1;
    //     return const Stream<List<String>>.empty().delay(Duration(seconds: delay)).concatWith([logStream(coreClient)]);
    //   });
    // }

    // // Create streams for both fg and bg clients with retry logic
    // final fgLogStream = logStream(core.fgClient);

    // if (core.bgClient == core.fgClient) {
    //   yield* fgLogStream;
    //   return;
    // }
    // final bgLogStream = logStream(core.bgClient);
    // yield* MergeStream([bgLogStream, fgLogStream]);
  }

  TaskEither<String, Unit> clearLogs() {
    return TaskEither(() async {
      loggy.debug("clearing logs");
      logBuffer.clear();
      // final res = await core.bgClient(Empty());
      // if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");
      return right(unit);
    });
  }

  TaskEither<String, WarpResponse> generateWarpConfig({
    required String licenseKey,
    required String previousAccountId,
    required String previousAccessToken,
  }) {
    return TaskEither(() async {
      loggy.debug("generating warp config");
      final warpConfig = await core.fgClient.generateWarpConfig(
        GenerateWarpConfigRequest(
          licenseKey: licenseKey,
          accountId: previousAccountId,
          accessToken: previousAccessToken,
        ),
      );
      // if (warpConfig.code != ResponseCode.OK) return left("${warpConfig.code} ${warpConfig.message}");
      final WarpResponse warp = (
        log: warpConfig.log,
        accountId: warpConfig.account.accountId,
        accessToken: warpConfig.account.accessToken,
        wireguardConfig: jsonEncode(warpConfig.config.toProto3Json()),
      );
      return right(warp);
    });
  }

  Stream<CoreStatus> watchStatus() async* {
    await startListeningStatus("bg", core.bgClient);
    yield* statusController.stream;
    // .endWith(const CoreStatus.stopped());
  }

  Future<void> startListeningStatus(String key, CoreClient cc) async {
    await listenSingle<CoreStatus>(
      "${key}StatusListener",
      () => cc
          .coreInfoListener(Empty(), options: grpcOptions)
          .doOnCancel(() {
            loggy.debug("status listener cancelled");
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .doOnData((event) {
            loggy.debug("status", event);
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .doOnDone(() {
            loggy.debug("status listener completed");
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .endWith(CoreInfoResponse(coreState: CoreStates.STOPPED))
          .map((event) {
            currentState = CoreStatus.fromCoreInfo(event);
            statusController.add(currentState);
            return currentState;
          }),
      // .endWith(const CoreStatus.stopped())
      onError: (error) {
        // Reported by listenSingle; logging again here is what produced two
        // lines per stream failure.

        // currentState = const CoreStatus.stopped();
        // statusController.add(currentState);

        // startListeningStatus(key, cc);
      },
    );
  }

  Future<void> startListeningLogs(String key, CoreClient cc) async {
    final listenKey = "${key}LogListener";
    // await stopListenSingle(listenKey);
    await listenSingle<LogMessage>(listenKey, () {
      // Subscribe at TRACE and let the core decide what to emit. Filtering by
      // level HERE was wrong twice over.
      //
      // It was stale: the level was read once with ref.read when the stream was
      // established, so changing it afterwards left the request pinned to the
      // old threshold for the life of the subscription.
      //
      // And it filtered on a label that does not mean anything for most lines.
      // Everything originating inside sing-box reaches us through
      // daemon.WriteMessage -> handler.WriteDebugMessage(message), which drops
      // the real severity and hard-codes log.LevelDebug, so every proxy, DNS and
      // routing line arrives tagged DEBUG whatever it actually was. With the
      // request pinned at info or warn, LogListener's `info.Level < req.Level`
      // check then discarded ALL of them — an empty Logs page rather than a
      // quieter one.
      //
      // Nothing is lost by widening it: both sources are already filtered at
      // source by the same user setting. sing-box lines only exist if they pass
      // options.Log.Level, and every message then passes PublishLog's
      // `level < static.logLevel` guard, which buildconfighelper.go sets from
      // that same setting. This request was a third application of it.
      return cc.logListener(LogRequest(level: LogLevel.TRACE), options: grpcOptions).map((event) {
        // Handle incoming event
        logBuffer.add(event);
        if (logBuffer.length > 300) {
          logBuffer.removeAt(0);
        }
        logController.add(logBuffer);
        // loggy.log(getLogLevel(event.level), event.message);
        event.message.split('\n').forEach((line) {
          loggy.log(getLogLevel(event.level), line);
        });
        return event;
      });
    });
  }

  Future<void> stopListenSingle(String key) async {
    // Collect keys to remove first
    final keysToRemove = subscriptions.entries
        .where((entry) => entry.key.startsWith(key))
        .map((entry) => entry.key)
        .toList();

    // Cancel and remove
    for (final k in keysToRemove) {
      final sub = subscriptions[k];
      await sub?.cancel(); // cancel the subscription

      subscriptions.remove(k);
    }
  }

  /// Report a stream failure at the severity it actually warrants.
  ///
  /// `UNAVAILABLE` means nothing is listening on the port. For the BACKGROUND
  /// core that is its normal resting state — it lives in the platform VPN
  /// service and does not exist until the tunnel starts — and the unary path
  /// has always treated it that way (see the `changeHiddifySettings` split).
  /// The stream path did not, so every launch emitted a burst of ERROR lines
  /// for a condition that is routine.
  ///
  /// That is not cosmetic. A foreground core that failed to start produces the
  /// SAME lines, so the one failure worth acting on was indistinguishable from
  /// the one that is expected, and an iOS import bug hid behind it. Hence the
  /// key check rather than a blanket demotion: `UNAVAILABLE` from the
  /// foreground core stays an error, because there it is one.
  void _logStreamError(String key, Object? error) {
    final backgroundNotStarted =
        key.startsWith("bg") && error is GrpcError && error.code == StatusCode.unavailable;
    if (backgroundNotStarted) {
      loggy.debug("$key: background core is not started yet");
      return;
    }
    loggy.error("Stream error in $key: $error");
  }

  Future<StreamSubscription<T>?> listenSingle<T>(
    String key,
    Stream<T> Function() stream, {
    Function(dynamic error)? onError,
  }) async {
    if (subscriptions.containsKey(key)) {
      // return subscriptions[key] as StreamSubscription<T>?;
      await stopListenSingle(key);
    }
    subscriptions[key] = null;
    subscriptions[key] = stream().listen(
      (event) {
        // loggy.debug(event);
      },
      cancelOnError: true,
      onError: (error) {
        _logStreamError(key, error);
        onError?.call(error);
        subscriptions[key]?.cancel();
        subscriptions.remove(key);
      },
    );
    return subscriptions[key] as StreamSubscription<T>?;
  }

  loggyl.LogLevel getLogLevel(LogLevel level) {
    return switch (level) {
      LogLevel.DEBUG => loggyl.LogLevel.debug,
      LogLevel.INFO => loggyl.LogLevel.info,
      LogLevel.WARNING => loggyl.LogLevel.warning,
      LogLevel.ERROR => loggyl.LogLevel.error,
      LogLevel.FATAL => loggyl.LogLevel.error,
      _ => loggyl.LogLevel.info, // Default case
    };
  }

// getCoreLogLevel lived here. Its only caller was startListeningLogs, which no
// longer maps the setting onto the subscription — see the note there.

  Future<void> closeFront() async {
    if (!core.isInitialized()) {
      return;
    }
    if (!core.isSingleChannel()) {
      await stopListenSingle("fg");
      await stopListenSingle("bg");
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL_INSECURE));
      } catch (e) {}
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL));
      } catch (e) {}
    }
  }
}
