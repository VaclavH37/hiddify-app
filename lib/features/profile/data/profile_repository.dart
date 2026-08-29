import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/db/db.dart';

import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/profile/data/profile_data_mapper.dart';
import 'package:hiddify/features/profile/data/profile_config_cipher.dart';
import 'package:hiddify/features/profile/data/profile_data_source.dart';
import 'package:hiddify/features/profile/data/profile_parser.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/config_slot.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/model/profile_failure.dart';
import 'package:hiddify/features/profile/model/profile_sort_enum.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/rayn_core_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:uuid/uuid.dart';

abstract interface class ProfileRepository {
  TaskEither<ProfileFailure, Unit> init();
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id);
  TaskEither<ProfileFailure, Unit> setAsActive(String id);
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive);
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile();
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile();
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  });
  /// [signal] and [counters] ride along as reachability telemetry. Neither
  /// changes what the middleware serves; the refresh is otherwise identical.
  ///
  /// The caller owns the counter window — it must clear what it sent only after
  /// this succeeds, so a failed delivery is re-sent rather than lost.
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    String? sourceToken,
    CancelToken? cancelToken,
    HubSignal? signal,
    HubCounters? counters,
  });
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride});
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity nProfile, String nContent);
  TaskEither<ProfileFailure, String> generateConfig(String id);
  TaskEither<ProfileFailure, String> getRawConfig(String id);

  /// Fetches the standby-hub config and seals it to the standby slot.
  ///
  /// Writes no Drift row and captures no headers: this is a cache the client
  /// keeps for itself, not an update to the subscription.
  TaskEither<ProfileFailure, Unit> refreshStandbyConfig(RemoteProfileEntity profile, {CancelToken? cancelToken});

  /// Opens the sealed config for [slot] and returns the normalised sing-box
  /// JSON, which is handed to the core in memory — never via a path.
  ///
  /// Defaults to [ConfigSlot.primary]: every caller that has no opinion about
  /// failover wants the config the middleware last served.
  TaskEither<ProfileFailure, String> readConfig(String id, {ConfigSlot slot = ConfigSlot.primary});
}

class ProfileRepositoryImpl with ExceptionHandler, InfraLogger implements ProfileRepository {
  ProfileRepositoryImpl({
    required ProfileDataSource profileDataSource,
    required ProfilePathResolver profilePathResolver,
    required RaynCoreService singbox,
    required ConfigOptionRepository configOptionRepository,
    required ProfileParser profileParser,
    required ProfileConfigCipher configCipher,
  }) : _configCipher = configCipher,
       _profileParser = profileParser,
       _configOptionRepo = configOptionRepository,
       _singbox = singbox,
       _profilePathResolver = profilePathResolver,
       _profileDataSource = profileDataSource;

  final ProfileDataSource _profileDataSource;
  final ProfilePathResolver _profilePathResolver;
  final RaynCoreService _singbox;
  final ConfigOptionRepository _configOptionRepo;
  final ProfileParser _profileParser;
  final ProfileConfigCipher _configCipher;

  @override
  TaskEither<ProfileFailure, Unit> init() {
    return exceptionHandler(() async {
      if (!kIsWeb) {
        if (!await _profilePathResolver.directory.exists()) {
          await _profilePathResolver.directory.create(recursive: true);
        }
      }

      await _enforceSingleProfileInvariant();

      return right(unit);
    }, ProfileUnexpectedFailure.new);
  }

  /// Reduces multi-profile installs to a single profile. Runs at every
  /// bootstrap; idempotent. Picks the active profile (or, if none, the
  /// most recently updated) and deletes the rest — both the Drift rows
  /// and their JSON config files. The auth-gate model only ever creates
  /// one profile, so this only matters once per upgrading user.
  Future<void> _enforceSingleProfileInvariant() async {
    final all = await _profileDataSource.watchAll(sort: ProfilesSort.lastUpdate, sortMode: SortMode.descending).first;
    if (all.length <= 1) {
      if (all.length == 1 && !all.first.active) {
        await _profileDataSource.edit(all.first.id, const ProfileEntriesCompanion(active: Value(true)));
      }
      return;
    }

    final keeper = all.firstWhere((p) => p.active, orElse: () => all.first);
    loggy.info('reducing ${all.length} profiles to single-profile install; keeping [${keeper.id}]');
    for (final p in all) {
      if (p.id == keeper.id) continue;
      await _profileDataSource.deleteById(p.id, false);
      await _deleteConfigFiles(p.id);
    }
    if (!keeper.active) {
      await _profileDataSource.edit(keeper.id, const ProfileEntriesCompanion(active: Value(true)));
    }
  }

  @override
  TaskEither<ProfileFailure, ProfileEntity?> getById(String id) {
    return TaskEither.tryCatch(
      () => _profileDataSource.getById(id).then((value) => value?.toEntity()),
      ProfileUnexpectedFailure.new,
    );
  }

  @override
  TaskEither<ProfileFailure, Unit> setAsActive(String id) {
    return TaskEither.tryCatch(() async {
      await _profileDataSource.edit(id, const ProfileEntriesCompanion(active: Value(true)));
      return unit;
    }, ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> deleteById(String id, bool isActive) {
    return TaskEither.tryCatch(() async {
      await _profileDataSource.deleteById(id, isActive);
      await _deleteConfigFiles(id);
      return unit;
    }, ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, ProfileEntity?>> watchActiveProfile() {
    return _profileDataSource.watchActiveProfile().map((event) => event?.toEntity()).handleExceptions((
      error,
      stackTrace,
    ) {
      loggy.error("error watching active profile", error, stackTrace);
      return ProfileUnexpectedFailure(error, stackTrace);
    });
  }

  @override
  Stream<Either<ProfileFailure, bool>> watchHasAnyProfile() {
    return _profileDataSource
        .watchProfilesCount()
        .map((event) => event != 0)
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  Stream<Either<ProfileFailure, List<ProfileEntity>>> watchAll({
    ProfilesSort sort = ProfilesSort.lastUpdate,
    SortMode sortMode = SortMode.ascending,
  }) {
    return _profileDataSource
        .watchAll(sort: sort, sortMode: sortMode)
        .map((event) => event.map((e) => e.toEntity()).toList())
        .handleExceptions(ProfileUnexpectedFailure.new);
  }

  @override
  TaskEither<ProfileFailure, Unit> upsertRemote(
    String url, {
    UserOverride? userOverride,
    String? sourceToken,
    CancelToken? cancelToken,
    HubSignal? signal,
    HubCounters? counters,
  }) =>
      TaskEither.tryCatch(
        () async => await _profileDataSource.getByUrl(url).then((profEntry) => profEntry?.toEntity()),
        ProfileFailure.unexpected,
      ).flatMap((profEntity) {
        // if profile is null, generate id
        final id = profEntity?.id ?? const Uuid().v4();
        if (profEntity != null && profEntity is RemoteProfileEntity) {
          // Update
          if (userOverride != null) {
            profEntity = profEntity.copyWith(userOverride: userOverride);
          }
          return _profileParser
              .updateRemote(
                rp: profEntity,
                cancelToken: cancelToken,
                signal: signal,
                counters: counters,
              )
              .flatMap((parsed) => _sealAndPersist(id: id, parsed: parsed, isUpdate: true));
        }
        // Add
        return _profileParser
            .addRemote(
              id: id,
              url: url,
              userOverride: userOverride,
              sourceToken: sourceToken,
              cancelToken: cancelToken,
            )
            .flatMap((parsed) => _sealAndPersist(id: id, parsed: parsed, isUpdate: false));
      });

  @override
  TaskEither<ProfileFailure, Unit> addLocal(String content, {UserOverride? userOverride}) {
    final id = const Uuid().v4();
    return _profileParser
        .addLocal(id: id, content: content, userOverride: userOverride)
        .flatMap((parsed) => _sealAndPersist(id: id, parsed: parsed, isUpdate: false));
  }

  @override
  TaskEither<ProfileFailure, Unit> offlineUpdate(ProfileEntity profile, String nContent) => TaskEither.tryCatch(
    () async => await _profileDataSource.getById(profile.id).then((profEntry) => profEntry?.toEntity()),
    ProfileFailure.unexpected,
  ).flatMap((oProfile) {
    if (oProfile == null || oProfile.runtimeType != profile.runtimeType) throw const ProfileFailure.notFound();
    if (profile.userOverride == null) loggy.warning('Updaing profile content with "userOverride" == null');
    final id = oProfile.id;
    return TaskEither.fromEither(
      _profileParser.offlineUpdate(
        profile: oProfile.copyWith(userOverride: profile.userOverride),
        content: nContent,
      ),
    ).flatMap((parsed) => _sealAndPersist(id: id, parsed: parsed, isUpdate: true));
  });

  /// Normalises the subscription body through the core, seals the result to
  /// `configs/<id>.enc`, then writes the Drift row.
  ///
  /// Ordering is deliberate and matches the previous file-based flow: the config
  /// is on disk before the row exists, so a crash mid-way leaves an orphaned
  /// file (harmless, overwritten on the next import) rather than a profile row
  /// pointing at a config that was never written.
  ///
  /// Nothing here touches a plaintext path. The core parses from `content` and
  /// hands the normalised JSON straight back — see `RaynCoreService.validateConfig`.
  TaskEither<ProfileFailure, Unit> _sealAndPersist({
    required String id,
    required ParsedProfile parsed,
    required bool isUpdate,
  }) => _validate(parsed.content, parsed.entry.profileOverride.value).flatMap(
    (normalised) => TaskEither.tryCatch(() async {
      final sealed = await _configCipher.encrypt(profileId: id, json: normalised);
      final target = _profilePathResolver.encFile(id);
      if (!await target.parent.exists()) await target.parent.create(recursive: true);
      await target.writeAsBytes(sealed, flush: true);
      // An older install may still have the plaintext next to it.
      await _deleteLegacyPlaintext(id);
      isUpdate ? await _profileDataSource.edit(id, parsed.entry) : await _profileDataSource.insert(parsed.entry);
      return unit;
    }, _mapCipherFailure),
  );

  /// Pushes the effective options into the core and parses [content], returning
  /// the normalised sing-box JSON.
  TaskEither<ProfileFailure, String> _validate(String content, String? profileOverride) =>
      TaskEither.fromEither(_configOptionRepo.fullOptionsOverrided(profileOverride))
          .mapLeft((configOptionFailure) => ProfileFailure.invalidConfig(null, configOptionFailure))
          .flatMap(
            (overridedOptions) => _singbox
                .changeOptions(overridedOptions)
                .mapLeft(ProfileFailure.invalidConfig)
                .flatMap((_) => _singbox.validateConfig(content).mapLeft(ProfileFailure.invalidConfig)),
          );

  ProfileFailure _mapCipherFailure(Object err, StackTrace st) => err is ConfigCipherException
      ? const ProfileFailure.configUnreadable()
      : ProfileFailure.unexpected(err, st);

  /// Removes every on-disk trace of a profile's config: the sealed file and any
  /// plaintext an older install left behind.
  Future<void> _deleteConfigFiles(String id) async {
    // EVERY slot, not just the primary. A standby blob left behind would keep
    // the standby hub's address on disk after a logout, which is the one
    // disclosure outcome the precache design cannot afford.
    for (final slot in ConfigSlot.values) {
      try {
        final sealed = _profilePathResolver.encFileForSlot(id, slot);
        if (await sealed.exists()) await sealed.delete();
      } catch (e) {
        loggy.warning('failed to delete sealed [${slot.name}] config for [$id]: ${e.runtimeType}');
      }
    }
    await _deleteLegacyPlaintext(id);
  }

  Future<void> _deleteLegacyPlaintext(String id) async {
    for (final f in [_profilePathResolver.legacyFile(id), _profilePathResolver.legacyTempFile(id)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (e) {
        loggy.warning('failed to remove legacy plaintext config for [$id]: ${e.runtimeType}');
      }
    }
  }

  @override
  TaskEither<ProfileFailure, Unit> refreshStandbyConfig(RemoteProfileEntity profile, {CancelToken? cancelToken}) =>
      _profileParser
          .fetchStandbyConfig(rp: profile, cancelToken: cancelToken)
          .flatMap((content) => _validate(content, profile.profileOverride))
          .flatMap((normalised) => _rejectIfSameHubAsPrimary(profile.id, normalised))
          .flatMap(
            (normalised) => TaskEither.tryCatch(() async {
              // Sealed under the SLOT's storage id, not the profile id — that
              // string is both this file's name and its AAD, and the native
              // readers reproduce it from the name (see configSlotStorageId).
              final sealed = await _configCipher.encrypt(
                profileId: configSlotStorageId(profile.id, ConfigSlot.standby),
                json: normalised,
              );
              final target = _profilePathResolver.encFileForSlot(profile.id, ConfigSlot.standby);
              if (!await target.parent.exists()) await target.parent.create(recursive: true);
              await target.writeAsBytes(sealed, flush: true);
              loggy.debug('standby config sealed for [${profile.id}]');
              return unit;
            }, _mapCipherFailure),
          );

  /// Refuses a standby body that dials the SAME hub as the stored primary.
  ///
  /// The tier header says a response *is* the standby projection; this checks
  /// that it actually dials somewhere else. Those are different claims, and the
  /// gap between them is the worst failure this design has — a primary config
  /// sealed into the standby slot makes a later failover swap primary for
  /// primary, restart the core and change nothing, while every log line says it
  /// worked.
  ///
  /// The middleware guards its own side (one hub address per body, and it fails
  /// closed rather than choosing between two of a tier), so this is defence in
  /// depth against a middleware bug or a misconfiguration, not a substitute for
  /// either. It costs one decrypt of a file we already hold and a hash of a body
  /// already in memory.
  ///
  /// A digest that cannot be computed on either side is NO OPINION, never a
  /// match: an unreadable stored primary must not stop us caching a perfectly
  /// good standby config.
  TaskEither<ProfileFailure, String> _rejectIfSameHubAsPrimary(String profileId, String standbyJson) =>
      TaskEither(() async {
    final standby = hubDigest(standbyJson);
    if (standby == null) return right(standbyJson);
    final primaryJson = (await readConfig(profileId).run()).toNullable();
    if (primaryJson == null) return right(standbyJson);
    if (standby != hubDigest(primaryJson)) return right(standbyJson);
    loggy.error('standby fetch returned the same hub as the primary config; refusing to cache it');
    return left(const ProfileFailure.invalidConfig('the standby projection dials the primary hub'));
  });

  @override
  TaskEither<ProfileFailure, String> readConfig(String id, {ConfigSlot slot = ConfigSlot.primary}) =>
      TaskEither(() async {
    // The file name and the AAD are the same string BY CONSTRUCTION. Deriving
    // them separately is what would let a standby blob be sealed under an id
    // the Kotlin and Swift readers cannot reproduce from the file name.
    final storageId = configSlotStorageId(id, slot);
    final file = _profilePathResolver.encFile(storageId);
    if (!await file.exists()) {
      loggy.warning('no stored config for [$storageId]');
      return left(const ProfileFailure.configUnreadable());
    }
    final result = await _configCipher.decrypt(profileId: storageId, blob: await file.readAsBytes());
    switch (result) {
      case ConfigDecryptOk(:final json):
        return right(json);
      case ConfigDecryptFailed(:final reason):
        // Report by reason — never by value; the plaintext is the user's node
        // list.
        //
        // Only discard the ciphertext when the blob itself is proven bad.
        // `keyUnavailable` means we could not read the KEY, which says nothing
        // about the config: a transient keystore failure (a DPAPI blip, the
        // Android Keystore not ready when `:bg` starts before the app has run,
        // an iOS keychain still locked before first unlock) would otherwise
        // destroy a perfectly good config and force a re-fetch the user cannot
        // perform offline — defeating the reason we keep an encrypted copy on
        // disk rather than going memory-only.
        final blobIsBad = reason != ConfigCipherRejection.keyUnavailable;
        loggy.error(
          'stored config for [$storageId] could not be opened (${reason.name})'
          '${blobIsBad ? "; discarding" : "; keeping it, the key was unreadable"}',
        );
        if (blobIsBad) {
          try {
            await file.delete();
          } catch (_) {}
        }
        return left(const ProfileFailure.configUnreadable());
    }
  });

  @override
  TaskEither<ProfileFailure, String> generateConfig(String id) =>
      readConfig(id).flatMap((content) => _singbox.generateFullConfig(content).mapLeft(ProfileFailure.unexpected));

  @override
  TaskEither<ProfileFailure, String> getRawConfig(String id) => readConfig(id);
}
