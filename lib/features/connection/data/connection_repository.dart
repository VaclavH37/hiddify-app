import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/config_slot.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/rayn_core_service.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

abstract interface class ConnectionRepository {
  SingboxConfigOption? get configOptionsSnapshot;

  TaskEither<ConnectionFailure, Unit> setup();
  Stream<ConnectionStatus> watchConnectionStatus();
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit);
  TaskEither<ConnectionFailure, Unit> disconnect();
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit);
}

class ConnectionRepositoryImpl with ExceptionHandler, InfraLogger implements ConnectionRepository {
  ConnectionRepositoryImpl({
    required this.ref,
    required this.directories,
    required this.singbox,
    required this.configOptionRepository,
    required this.profilePathResolver,
  });

  final Ref ref;

  final Directories directories;
  final RaynCoreService singbox;

  final ConfigOptionRepository configOptionRepository;
  final ProfilePathResolver profilePathResolver;

  SingboxConfigOption? _configOptionsSnapshot;
  @override
  SingboxConfigOption? get configOptionsSnapshot => _configOptionsSnapshot;

  bool _initialized = false;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    if (_initialized) return TaskEither.of(unit);
    return exceptionHandler(() {
      loggy.debug("setting up singbox");

      return singbox
          .setup()
          .map((r) {
            _initialized = true;
            return r;
          })
          .mapLeft(UnexpectedConnectionFailure.new)
          .run();
    }, UnexpectedConnectionFailure.new);
  }

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    return singbox.watchStatus().map(
      (event) => switch (event) {
        CoreStopped() => Disconnected(event.getCoreAlert()),
        CoreStarting() => const Connecting(),
        CoreStarted() => const Connected(),
        CoreStopping() => const Disconnecting(),
      },
    );
  }

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      setup().flatMap(
        (_) => applyConfigOption(activeProfile).flatMap(
          (_) => _readConfig(activeProfile.id).flatMap(
            (opened) => singbox.start(
              // The path of the slot we OPENED, not of the primary. It is
              // handed to the platform shell and kept as `activeConfigPath`, so
              // that a start the system initiates on its own — quick-settings
              // tile, always-on, iOS on-demand — decrypts the same config this
              // connect chose. Naming the primary here would send exactly those
              // starts back to a hub we just failed away from.
              profilePathResolver.encFileForSlot(activeProfile.id, opened.slot).path,
              opened.content,
              activeProfile.name,
              disableMemoryLimit,
            ),
          ),
        ),
      );

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => singbox.stop().mapLeft(UnexpectedConnectionFailure.new);

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      applyConfigOption(activeProfile).flatMap(
        (_) => _readConfig(activeProfile.id).flatMap(
          (opened) => singbox
              .restart(opened.content, activeProfile.name, disableMemoryLimit)
              .mapLeft(UnexpectedConnectionFailure.new),
        ),
      );

  /// Opens the active slot's sealed config so the plaintext exists only in
  /// memory, for the moment it takes to hand it to the core.
  ///
  /// Reports which slot it opened, because that decides the path handed to the
  /// platform shell — and after the fallback below, the slot opened is not
  /// necessarily the slot asked for.
  ///
  /// A failure here means the stored config is gone or unreadable — a wiped
  /// platform keystore, a restore to a new device, or a downgraded install. The
  /// remedy is always a subscription re-fetch, which the profile layer performs
  /// on the next refresh; surfacing it as a connection failure is what tells the
  /// user to go online rather than leaving them staring at a spinner.
  TaskEither<ConnectionFailure, ({String content, ConfigSlot slot})> _readConfig(String profileId) =>
      TaskEither(() async {
    final prefs = ref.read(sharedPreferencesProvider).requireValue;
    final repository = ref.read(profileRepositoryProvider).requireValue;
    var slot = configSlotOf(prefs.getString(activeConfigSlotKey));

    var content = (await repository.readConfig(profileId, slot: slot).run()).toNullable();

    // NEVER leave the user with no config because a precached one is missing.
    // The standby blob is an optimisation the client wrote for itself, and it
    // is legitimately absent on a fresh install, after a failed standby fetch,
    // or once its key has been rotated away. The primary is the config the
    // subscription actually paid for, so fall back to it and forget the forced
    // slot — the reachability ladder will detect the hub again and re-escalate
    // if the primary really is still blocked.
    if (content == null && slot != ConfigSlot.primary) {
      loggy.warning("no usable [${slot.name}] config; falling back to the primary slot");
      await prefs.remove(activeConfigSlotKey);
      slot = ConfigSlot.primary;
      content = (await repository.readConfig(profileId, slot: slot).run()).toNullable();
    }

    if (content == null) {
      return left(const ConnectionFailure.unexpected("stored configuration is unavailable; refresh the subscription"));
    }
    await _dumpForDebug(content);
    return right((content: content, slot: slot));
  });

  /// Debug builds only: writes the decrypted profile config to
  /// `<workingDir>/data/debug-profile-config.json` on every connect.
  ///
  /// `kDebugMode` is a compile-time const, so in release AOT this branch and its
  /// string literals are dead-code-eliminated outright — the same property the
  /// `rayn://` key masking relies on. That matters here: a runtime flag would
  /// not be safe, because every flag the core exposes is user-reachable and the
  /// loopback gRPC channel is unauthenticated.
  ///
  /// This is the config as the API delivered it. To inspect the *built* config —
  /// our routing rules, DNS servers, inbounds and balancer groups — rebuild the
  /// core with `EXTRA_TAGS=raynconfigdump` (see `v2/hcore/configdump.go`).
  Future<void> _dumpForDebug(String content) async {
    if (kDebugMode) {
      try {
        final file = File(p.join(directories.workingDir.path, 'data', 'debug-profile-config.json'));
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsString(content, flush: true);
      } catch (e) {
        loggy.warning('debug config dump failed (${e.runtimeType})');
      }
    }
  }

  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> applyConfigOption(ProfileEntity prof) =>
      TaskEither.fromEither(configOptionRepository.fullOptionsOverrided(prof.profileOverride))
          .mapLeft((l) => ConnectionFailure.invalidConfigOption(null, l))
          .flatMap(
            (overridedOptions) => TaskEither.tryCatch(() async {
              _configOptionsSnapshot = overridedOptions;
              await singbox.changeOptions(overridedOptions).run();
              return unit;
            }, (err, st) => err is ConnectionFailure ? err : ConnectionFailure.unexpected(err, st)),
          );
}
