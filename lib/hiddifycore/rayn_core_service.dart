import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper_stub.dart'
    if (dart.library.io) 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper.dart';
import 'package:hiddify/hiddifycore/core_stream_errors.dart';
import 'package:hiddify/hiddifycore/foreground_retry.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/warp_account.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart' as loggyl;
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
      final ParseResponse response;
      try {
        // Heals on ANY first failure, not only an unreachable core: this call
        // has always re-run setup for whatever went wrong, and every failure,
        // first or second, has to come back as a Left. It used to escape this
        // TaskEither as a raw exception, which is how "the core is not
        // listening" reached the user as `Failed to add profile: Unexpected
        // error Error connecting: SocketException ... port 49465` — an
        // ephemeral LOCAL port, which reads like a network fault and names
        // nothing that exists in this codebase. The real destination is the
        // foreground core on 127.0.0.1.
        response = await callForegroundCore(
          call: () => core.fgClient.parse(ParseRequest(content: content, debug: false)),
          heal: _healForeground,
          shouldHeal: (_) => true,
        );
      } on ForegroundCoreUnreachable catch (e) {
        return left(
          _unreachableMessage(e, "cannot reach the local core to validate the configuration: ${e.lastError}"),
        );
      }
      if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      return right(response.content);
    });
  }

  TaskEither<String, String> generateFullConfig(String content) {
    return TaskEither(() async {
      final ParseResponse response;
      try {
        response = await callForegroundCore(
          call: () => core.fgClient.parse(ParseRequest(content: content, debug: false)),
          heal: _healForeground,
        );
      } on ForegroundCoreUnreachable catch (e) {
        return left(_unreachableMessage(e, "cannot reach the local core to build the configuration: ${e.lastError}"));
      }
      if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      return right(response.content);
    });
  }

  /// The heal [callForegroundCore] runs once before retrying: set the core up
  /// again, which also restarts a foreground server that stopped listening (see
  /// keepOrReviveLocked in the core's grpc_server.go). Returns why setup failed,
  /// or null.
  Future<String?> _healForeground(Object error) async {
    loggy.warning("the local core was unreachable; restarting it and retrying once", error);
    return (await setup().run()).getLeft().toNullable();
  }

  /// Prefers setup's own failure: it says WHY the core did not come up, where
  /// the retried call only says that it is absent.
  static String _unreachableMessage(ForegroundCoreUnreachable e, String otherwise) =>
      e.healError != null ? "core did not start: ${e.healError}" : otherwise;

  /// Restarts the foreground core if it stopped listening while the app was in
  /// the background.
  ///
  /// iOS may reclaim the resources under a suspended app's sockets, after which
  /// the foreground core refuses every connection. The pause handler cannot be
  /// relied on to release the core first: it runs on a rebuild, and Flutter
  /// stops producing frames once the app is hidden. Checking on resume catches
  /// the loss before the user's next import does.
  ///
  /// A loopback connect, so cheap enough for every resume. Always true on
  /// desktop, where the base [CoreInterface.isActiveFg] says so.
  Future<void> reviveForegroundIfDead() async {
    if (await core.isActiveFg()) return;
    loggy.warning("the local core stopped listening while the app was in the background; restarting it");
    await init();
  }

  /// One setup at a time. Bootstrap, the connection repository, resume and every
  /// heal all call [setup]; overlapping calls share one run instead of each
  /// rebuilding the clients and re-subscribing the streams.
  final _setupFlight = SingleFlight<Either<String, Unit>>();

  TaskEither<String, Unit> setup() => TaskEither(() => _setupFlight.run(_setup().run));

  TaskEither<String, Unit> _setup() {
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
      //
      // The foreground call gets one heal-and-retry: this is the call a profile
      // import makes first, so a foreground core that stopped listening while
      // the app was suspended used to fail the import here with no retry at
      // all, and keep failing until the app was force-quit.
      try {
        final res = await callForegroundCore(
          call: () => core.fgClient.changeHiddifySettings(ChangeHiddifySettingsRequest(hiddifySettingsJson: payload)),
          heal: _healForeground,
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
      } on ForegroundCoreUnreachable catch (e) {
        loggy.error("foreground core is unreachable", e.lastError);
        final reason = switch (e.lastError) {
          final GrpcError error => error.message ?? error.codeName,
          final other => "$other",
        };
        return left(_unreachableMessage(e, "cannot reach the local core to apply settings: $reason"));
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
    // Held until the core runs. On iOS the tunnel comes up first and then waits
    // for the `Start` below, which an app suspended in between never sends.
    return TaskEither(
      () => core.withBackgroundTime(() => _whileStarting(() => _start(sealedPath, content, name, disableMemoryLimit))),
    );
  }

  /// Set while a start is under way: the status stream holds back a plain
  /// "stopped" until it is over (see [coreStatusIsNews]).
  bool _startInFlight = false;

  /// Runs [start] with [_startInFlight] set.
  ///
  /// A start that fails without publishing its outcome (a gRPC error on
  /// `Start`) used to leave the "stopped" the stream opened with on screen. That
  /// one is now held back, so it is published here instead.
  Future<Either<ConnectionFailure, Unit>> _whileStarting(
    Future<Either<ConnectionFailure, Unit>> Function() start,
  ) async {
    _startInFlight = true;
    try {
      final result = await start();
      if (result.isLeft() && currentState is CoreStarting) {
        statusController.add(currentState = const CoreStatus.stopped());
      }
      return result;
    } finally {
      _startInFlight = false;
    }
  }

  /// Runs [body] with the app kept alive until it finishes (see
  /// `CoreInterface.withBackgroundTime`): for work that spans a core restart.
  Future<T> withBackgroundTime<T>(Future<T> Function() body) => core.withBackgroundTime(body);

  Future<Either<ConnectionFailure, Unit>> _start(
    String sealedPath,
    String content,
    String name,
    bool disableMemoryLimit,
  ) async {
    statusController.add(currentState = const CoreStatus.starting());
    loggy.debug("starting");
    // Before the start, so the start's own lines are caught.
    await _reopenLogStreamIfDead();
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
  }

  TaskEither<String, Unit> stop() {
    return TaskEither(() async {
      loggy.debug("stopping");
      var errMsg = "";
      try {
        await core.bgClient.stop(Empty());
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
            final status = CoreStatus.fromCoreInfo(event);
            if (!coreStatusIsNews(status, startInFlight: _startInFlight)) {
              loggy.debug("not yet started; a start is under way");
              return currentState;
            }
            currentState = status;
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

  /// Reopens the core's log stream on desktop if a connection reset killed it.
  ///
  /// Desktop runs one channel for both clients, and setup() is the only other
  /// place that opens the log stream; start() reopens streams on mobile only.
  /// A connection reset kills every stream on that channel (see
  /// [coreStreamErrorLevel]), and a core restart makes one likely: after the
  /// first live failover on Windows (2026-10-18) no core line reached the app
  /// or an exported log for the rest of the session, the egress-routing line
  /// included. The status stream already recovers through watchStatus.
  Future<void> _reopenLogStreamIfDead() async {
    if (!core.isInitialized() || !core.isSingleChannel()) return;
    if (subscriptions.containsKey("fgLogListener")) return;
    loggy.info("reopening the core log stream");
    await startListeningLogs("fg", core.fgClient);
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

  /// Report a stream failure at the severity it actually warrants; the rules
  /// are [coreStreamErrorLevel]'s.
  void _logStreamError(String key, Object? error) {
    switch (coreStreamErrorLevel(key, error)) {
      case CoreStreamErrorLevel.debug:
        loggy.debug("$key: background core is not started yet");
      case CoreStreamErrorLevel.warning:
        loggy.warning(
          "$key: the connection to the core was reset; the stream reopens when the core next starts",
          error,
        );
      case CoreStreamErrorLevel.error:
        loggy.error("Stream error in $key: $error");
    }
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
    late final StreamSubscription<T> subscription;
    subscription = stream().listen(
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
      // A stream that ended is gone too, so that an entry here always means a
      // live stream (see _reopenLogStreamIfDead). Only this subscription's own
      // entry: a replacement registered under the key since is left alone.
      onDone: () {
        if (identical(subscriptions[key], subscription)) subscriptions.remove(key);
      },
    );
    subscriptions[key] = subscription;
    return subscription;
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
      } catch (_) {
        // Best effort: the server for this mode may already be gone.
      }
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL));
      } catch (_) {
        // Best effort, as above.
      }
    }
  }
}
