import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:hiddify/features/connection/local_routing/model/egress_routing.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_desktop.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'egress_routing_probe.g.dart';

/// Reads the egress adapter's routing switches from the core. Null means
/// "nothing to report": not Windows, an older core without the export, or a
/// question the core could not answer.
abstract interface class EgressRoutingProbe {
  EgressRouting? read();
}

@Riverpod(keepAlive: true)
EgressRoutingProbe egressRoutingProbe(Ref ref) =>
    PlatformUtils.isWindows ? FfiEgressRoutingProbe(() => CoreInterfaceDesktop.library) : const NoEgressRoutingProbe();

class NoEgressRoutingProbe implements EgressRoutingProbe {
  const NoEgressRoutingProbe();

  @override
  EgressRouting? read() => null;
}

typedef _EgressRoutingNative = Pointer<Utf8> Function();
typedef _FreeStringDart = void Function(Pointer<Utf8>);

/// Calls the core's `raynEgressRouting` export directly, the way `setup` is
/// called: a synchronous call that takes microseconds while a tunnel runs,
/// with no gRPC method (and no proto regeneration) behind it.
///
/// The string belongs to the core's C runtime and goes back through its own
/// `freeString`; package:ffi's allocators are a different heap on Windows.
class FfiEgressRoutingProbe with InfraLogger implements EgressRoutingProbe {
  FfiEgressRoutingProbe(this._open);

  final DynamicLibrary Function() _open;

  ({_EgressRoutingNative call, _FreeStringDart free})? _bound;
  bool _unavailable = false;

  @override
  EgressRouting? read() {
    final bound = _bind();
    if (bound == null) return null;
    final answer = bound.call();
    if (answer == nullptr) return null;
    try {
      return EgressRouting.fromJson(jsonDecode(answer.toDartString()));
    } catch (error) {
      loggy.warning("egress routing: unreadable answer from the core", error);
      return null;
    } finally {
      bound.free(answer);
    }
  }

  ({_EgressRoutingNative call, _FreeStringDart free})? _bind() {
    if (_unavailable) return null;
    final bound = _bound;
    if (bound != null) return bound;
    try {
      final library = _open();
      // An older core has no such export; one look is enough for the session.
      if (!library.providesSymbol('raynEgressRouting') || !library.providesSymbol('freeString')) {
        loggy.info("egress routing: this core has no raynEgressRouting export; the IP routing check is off");
        _unavailable = true;
        return null;
      }
      return _bound = (
        call: library.lookupFunction<_EgressRoutingNative, _EgressRoutingNative>('raynEgressRouting'),
        free: library.lookupFunction<Void Function(Pointer<Utf8>), _FreeStringDart>('freeString'),
      );
    } catch (error) {
      loggy.info("egress routing: core library unavailable; the IP routing check is off", error);
      _unavailable = true;
      return null;
    }
  }
}
