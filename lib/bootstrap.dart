import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/logger/logger.dart';
import 'package:hiddify/core/logger/logger_controller.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_migration.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/rulesets/ruleset_extractor.dart';
import 'package:hiddify/features/app/widget/app.dart';
import 'package:hiddify/features/profile/data/config_at_rest_migration.dart';
import 'package:hiddify/features/profile/data/profile_config_cipher.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/features/system_tray/notifier/system_tray_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/hiddifycore/rayn_core_service_provider.dart';
import 'package:hiddify/riverpod_observer.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> lazyBootstrap(WidgetsBinding widgetsBinding, Environment env) async {
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }
  LoggerController.preInit();
  FlutterError.onError = Logger.logFlutterError;
  WidgetsBinding.instance.platformDispatcher.onError = Logger.logPlatformDispatcherError;

  final stopWatch = Stopwatch()..start();

  final container = ProviderContainer(overrides: [environmentProvider.overrideWithValue(env)]);

  await _init("directories", () => container.read(appDirectoriesProvider.future));
  LoggerController.init(container.read(logPathResolverProvider).appFile().path);

  // Extract bundled CN rule-sets into the Go core's working directory. Must
  // run before the Go core boots so `Type: Local` rule-sets in builder.go can
  // load: the core os.Chdir()s to the working path and resolves relative Local
  // rule-set paths against it (CWD), so a .srs written anywhere else makes every
  // `RuleSet:`-keyed rule fail to open and the core refuses to start.
  //
  // baseDir and workingDir are now the same directory on every platform. They
  // used to diverge on Android, where workingDir was the external files dir —
  // see `_migrateAndroidWorkingDir`. Keep passing workingDir explicitly: it is
  // the contract the core actually depends on.
  await _safeInit("rulesets", () async {
    final dirs = await container.read(appDirectoriesProvider.future);
    await RulesetExtractor.ensureExtracted(dirs.workingDir);
  });

  final appInfo = await _init("app info", () => container.read(appInfoProvider.future));
  await _init("preferences", () => container.read(sharedPreferencesProvider.future));
  await _init("rayn token decryptor", () => RaynTokenDecryptor.load());

  await _init("preferences migration", () async {
    try {
      await PreferencesMigration(sharedPreferences: container.read(sharedPreferencesProvider).requireValue).migrate();
    } catch (e, stackTrace) {
      Logger.bootstrap.error("preferences migration failed", e, stackTrace);
      if (env == Environment.dev) rethrow;
      Logger.bootstrap.info("clearing preferences");
      await container.read(sharedPreferencesProvider).requireValue.clear();
    }
  });

  // Compile-time only. This used to read the Debug mode preference OR'd with
  // kDebugMode — which meant a debug build was always `true` regardless of the
  // toggle, so the switch only ever had an effect in RELEASE builds. Exactly
  // backwards: it did nothing for developers and everything for an adversary.
  //
  // Now a debug build is always on and a shipped build always off, including for
  // installs that already have `true` persisted from an older version.
  const debug = kDebugMode;

  if (PlatformUtils.isDesktop) {
    await _init("window controller", () => container.read(windowNotifierProvider.future));

    final silentStart = container.read(Preferences.silentStart);
    Logger.bootstrap.debug("silent start [${silentStart ? "Enabled" : "Disabled"}]");
    if (!silentStart) {
      await container.read(windowNotifierProvider.notifier).show(focus: false);
    } else {
      Logger.bootstrap.debug("silent start, remain hidden accessible via tray");
    }
    await _init("auto start service", () => container.read(autoStartNotifierProvider.future));
  }
  await _init("logs repository", () => container.read(logRepositoryProvider.future));
  await _init("logger controller", () => LoggerController.postInit(debug));

  Logger.bootstrap.info(appInfo.format());

  await _init("profile repository", () => container.read(profileRepositoryProvider.future));

  // Seal any plaintext config an older install left behind and remove the
  // debug artefact the Go core used to write. Best-effort: a failure here must
  // not block startup — the config is re-derivable from the subscription.
  await _safeInit("config at-rest migration", () async {
    await ConfigAtRestMigration(
      pathResolver: container.read(profilePathResolverProvider),
      cipher: container.read(profileConfigCipherProvider),
      workingDir: (await container.read(appDirectoriesProvider.future)).workingDir,
    ).run();
  });

  await _init("translations", () => container.read(translationsProvider.future));

  await _safeInit("active profile", () => container.read(activeProfileProvider.future), timeout: 1000);
  // _safeInit, not _init: a throw here used to kill lazyBootstrap outright, so a
  // core that failed to initialise took the whole app down at launch rather than
  // surfacing as a connection failure the user can see and retry. Every other
  // fallible step in this function is already _safeInit for the same reason.
  await _safeInit("rayn-core", () => container.read(raynCoreServiceProvider).init());

  // Force activeProxyNotifierProvider to evaluate eagerly, here, rather than
  // lazily on first read from the home page. Its first build would otherwise be
  // flushed part-way through building a sibling that shares its dependencies,
  // which is the collision this whole change is about.
  container.listen(activeProxyNotifierProvider, (_, _) {});

  if (!kIsWeb) {
    // await _safeInit(
    //   "deep link service",
    //   () => container.read(deepLinkNotifierProvider.future),
    //   timeout: 1000,
    // );

    if (PlatformUtils.isDesktop) {
      // Skip eager tray init pre-auth: with no profile loaded, the tray's
      // gRPC status query has nothing to wait on and will hit the timeout,
      // logging spurious cancel errors. The App widget's conditional
      // listener (gated on hasAnyProfile) picks it up after auth instead.
      final hasProfile = container.read(hasAnyProfileProvider).valueOrNull ?? false;
      if (hasProfile) {
        await _safeInit("system tray", () => container.read(systemTrayNotifierProvider.future), timeout: 1000);
      } else {
        Logger.bootstrap.debug("system tray init deferred — no authenticated profile");
      }
    }

    if (PlatformUtils.isAndroid) {
      await _safeInit("android display mode", () async {
        await FlutterDisplayMode.setHighRefreshRate();
      });
    }
  }

  Logger.bootstrap.info("bootstrap took [${stopWatch.elapsedMilliseconds}ms]");
  stopWatch.stop();

  runApp(
    ProviderScope(
      parent: container,
      observers: [RiverpodObserver()],
      child: const App(),
    ),
  );

  if (!kIsWeb) {
    FlutterNativeSplash.remove();
  }
}

Future<T> _init<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  final stopWatch = Stopwatch()..start();
  Logger.bootstrap.info("initializing [$name]");
  Future<T> func() => timeout != null ? initializer().timeout(Duration(milliseconds: timeout)) : initializer();
  try {
    final result = await func();
    Logger.bootstrap.debug("[$name] initialized in ${stopWatch.elapsedMilliseconds}ms");
    return result;
  } catch (e, stackTrace) {
    Logger.bootstrap.error("[$name] error initializing", e, stackTrace);
    rethrow;
  } finally {
    stopWatch.stop();
  }
}

Future<T?> _safeInit<T>(String name, Future<T> Function() initializer, {int? timeout}) async {
  try {
    return await _init(name, initializer, timeout: timeout);
  } catch (e) {
    return null;
  }
}
