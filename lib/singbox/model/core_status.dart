import 'package:dartx/dartx.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

part 'core_status.freezed.dart';

@freezed
sealed class CoreStatus with _$CoreStatus {
  const CoreStatus._();

  const factory CoreStatus.stopped({CoreAlert? alert, String? message}) = CoreStopped;
  const factory CoreStatus.starting() = CoreStarting;
  const factory CoreStatus.started() = CoreStarted;
  const factory CoreStatus.stopping() = CoreStopping;

  factory CoreStatus.fromEvent(dynamic event) {
    final map = event as Map<String, dynamic>?;
    switch (map?["status"]) {
      case "Stopped":
        final alertstr = map?["alert"] as String?;
        var msgStr = map?["message"] as String?;
        var alert = CoreAlert.values.firstOrNullWhere((e) => alertstr?.toLowerCase() == e.name.toLowerCase());
        if ((alert == null) && (alertstr ?? "") != "") {
          msgStr = ((msgStr ?? "") != "") ? "$alertstr: $msgStr" : alertstr;
          alert = CoreAlert.unknown;
        }
        return CoreStatus.stopped(alert: alert, message: msgStr);

      case "Starting":
        return const CoreStarting();
      case "Started":
        return const CoreStarted();
      case "Stopping":
        return const CoreStopping();
      default:
        throw Exception("unexpected status [$map]");
    }
  }
  factory CoreStatus.fromCoreInfo(CoreInfoResponse event) {
    switch (event.coreState) {
      case CoreStates.STOPPED:
        final CoreAlert? alert = switch (event.messageType) {
          MessageType.EMPTY => null,
          MessageType.ERROR_READING_CONFIG => CoreAlert.emptyConfiguration,
          MessageType.START_COMMAND_SERVER => CoreAlert.startCommandServer,
          MessageType.CREATE_SERVICE => CoreAlert.createService,
          MessageType.START_SERVICE => CoreAlert.startService,
          MessageType.UNEXPECTED_ERROR => CoreAlert.startService,
          MessageType.INSTANCE_NOT_STOPPED => CoreAlert.startService,
          MessageType.INSTANCE_NOT_STARTED => CoreAlert.startService,
          MessageType.INSTANCE_NOT_FOUND => CoreAlert.startService,
          MessageType.ERROR_PARSING_CONFIG => CoreAlert.emptyConfiguration,
          MessageType.ERROR_BUILDING_CONFIG => CoreAlert.emptyConfiguration,
          MessageType.EMPTY_CONFIGURATION => CoreAlert.emptyConfiguration,
          // Not a failure. On Android and iOS the platform shell stops the core
          // a second time when it tears the tunnel down (`Mobile.close` calls
          // `Stop()`), and that stop finds nothing running. Read as
          // createService, every mobile disconnect reported a connection
          // failure (2026-10-19).
          MessageType.ALREADY_STOPPED => null,
          MessageType.ALREADY_STARTED => CoreAlert.startService,

          // MessageType.REQUEST_VPN_PERMISSION => SingboxAlert.requestVPNPermission,
          // MessageType.REQUEST_NOTIFICATION_PERMISSION => SingboxAlert.requestNotificationPermission,
          _ => CoreAlert.emptyConfiguration, // Default case
        };
        return CoreStatus.stopped(alert: alert, message: event.message);
      case CoreStates.STARTING:
        return const CoreStarting();
      case CoreStates.STARTED:
        return const CoreStarted();
      case CoreStates.STOPPING:
        return const CoreStopping();
      default:
        throw Exception("unexpected status [$event]");
    }
  }

  ConnectionFailure? getCoreAlert() {
    return switch (this) {
      CoreStopped(alert: final alert, message: final message) when alert != null => switch (alert) {
        CoreAlert.emptyConfiguration => ConnectionFailure.invalidConfig(message),

        CoreAlert.requestNotificationPermission => ConnectionFailure.missingNotificationPermission(message),

        CoreAlert.requestVPNPermission => ConnectionFailure.missingVpnPermission(message),

        CoreAlert.startCommandServer ||
        CoreAlert.createService ||
        CoreAlert.startService ||
        CoreAlert.alreadyStarted ||
        CoreAlert.startFailed => ConnectionFailure.unexpected("${alert.name} - $message"),

        _ => null,
      },

      _ => null,
    };
  }
}

/// Whether a status from the core's own stream is news to the app.
///
/// While the app is starting the core, a plain "stopped" is not. The core
/// truthfully reports it until the app's `Start` reaches it, and a status stream
/// opened in that gap (every mobile start, and an iOS resume mid-start) opens
/// with it. Published, it flipped Connecting to Disconnected: for milliseconds
/// on Android, and for 3.2 s on iOS in the 2026-10-19 failover, with the orb
/// offering "Tap to connect" over a start still under way. A stop that carries
/// an alert is a failure and always news.
bool coreStatusIsNews(CoreStatus status, {required bool startInFlight}) =>
    !startInFlight || status is! CoreStopped || status.alert != null;

enum CoreAlert {
  requestVPNPermission,
  requestNotificationPermission,
  emptyConfiguration,
  startCommandServer,
  createService,
  startService,
  alreadyStarted,
  startFailed,
  unknown,
}
