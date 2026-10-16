import 'package:flutter/foundation.dart';

/// What the core reports about the adapter its own connections leave through:
/// the `raynEgressRouting` export, `hiddify-core/v2/config/egress_routing.go`.
///
/// Why it matters (reproduced on Windows 11, 2026-10-16): with IPv4 forwarding
/// on for that adapter, Windows stops honouring the interface binding on the
/// core's sockets. Its hub and direct connections then go into the tunnel
/// instead of out of the adapter, the core refuses them as a loop, and the app
/// sits on "Connected" while nothing gets through. Turning forwarding off on
/// the adapter fixes it within a second, with no reconnect.
@immutable
class EgressRouting {
  const EgressRouting({
    required this.index,
    required this.alias,
    required this.forwarding,
    this.forwarding6 = false,
    this.weakHostSend = false,
  });

  /// The interface index, which `netsh` accepts in place of the name.
  final int index;

  /// The adapter's name as Windows shows it, so already in the user's language.
  final String alias;

  /// IPv4 forwarding: the setting the reproduction proved.
  final bool forwarding;

  /// Reported for the log, never acted on: neither has been tested on its own.
  final bool forwarding6;
  final bool weakHostSend;

  /// Parses the core's JSON. Null when the core did not check (not Windows, or
  /// the system tables did not answer) or the payload is not what it writes:
  /// either way there is nothing to tell the user.
  static EgressRouting? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    if (json['checked'] != true) return null;
    final index = json['index'];
    final alias = json['alias'];
    final forwarding = json['forwarding'];
    if (index is! int || index <= 0 || alias is! String || alias.isEmpty || forwarding is! bool) return null;
    return EgressRouting(
      index: index,
      alias: alias,
      forwarding: forwarding,
      forwarding6: json['forwarding6'] == true,
      weakHostSend: json['weak_host_send'] == true,
    );
  }

  /// Whether this adapter is in the state proven to stop the tunnel.
  bool get blocksTunnel => forwarding;

  /// The one-line fix for an administrator Command Prompt. It uses the index,
  /// so it needs no quoting and works on a Windows in any language. It lasts
  /// until something turns forwarding back on (Routing and Remote Access does
  /// when it starts), which is why the dialog leads with removing the cause.
  String get fixCommand => 'netsh interface ipv4 set interface $index forwarding=disabled';

  @override
  bool operator ==(Object other) =>
      other is EgressRouting &&
      other.index == index &&
      other.alias == alias &&
      other.forwarding == forwarding &&
      other.forwarding6 == forwarding6 &&
      other.weakHostSend == weakHostSend;

  @override
  int get hashCode => Object.hash(index, alias, forwarding, forwarding6, weakHostSend);

  @override
  String toString() =>
      'egress adapter "$alias" (index $index): forwarding=${_onOff(forwarding)} '
      'forwarding6=${_onOff(forwarding6)} weak-host-send=${_onOff(weakHostSend)}';

  static String _onOff(bool on) => on ? 'on' : 'off';
}
