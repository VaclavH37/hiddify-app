import 'package:flutter/material.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';

import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'general_preferences.g.dart';

abstract class Preferences {
  static final windowMaximized = PreferencesNotifier.create<bool, bool>("window_maximized", false);

  static final windowPosition = PreferencesNotifier.create<Offset?, String?>(
    "window_position",
    null,
    mapFrom: (value) {
      if (value == null) return null;
      final list = value.split(',').map((e) => double.tryParse(e)).toList();
      return Offset(list[0]!, list[1]!);
    },
    mapTo: (value) {
      if (value == null) return null;
      return "${value.dx},${value.dy}";
    },
  );

  static final windowSize = PreferencesNotifier.create<Size, String>(
    "window_size",
    defaultWindowSize,
    mapFrom: (value) {
      final list = value.split(',').map((e) => double.tryParse(e)).toList();
      return Size(list[0]!, list[1]!);
    },
    mapTo: (value) => "${value.width},${value.height}",
  );

  static final silentStart = PreferencesNotifier.create<bool, bool>("silent_start", false);

  static final disableMemoryLimit = PreferencesNotifier.create<bool, bool>(
    "disable_memory_limit",
    // disable memory limit on desktop by default
    PlatformUtils.isDesktop,
  );

  static final markNewProfileActive = PreferencesNotifier.create<bool, bool>("mark_new_profile_active", true);

  static final dynamicNotification = PreferencesNotifier.create<bool, bool>("dynamic_notification", true);

  static final startedByUser = PreferencesNotifier.create<bool, bool>("started_by_user", false);

  static final storeReviewedByUser = PreferencesNotifier.create<bool, bool>("store_reviewed_by_user", false);

  // Google Play prominent-disclosure consent flags (mobile only). Two SEPARATE
  // disclosures per policy: the VpnService disclosure must not be combined with
  // the personal/sensitive-data disclosure, so each has its own affirmative
  // consent and its own flag. Gated in the router redirect before `/auth`.
  static final vpnDisclosureAccepted = PreferencesNotifier.create<bool, bool>("vpn_disclosure_accepted", false);

  static final dataDisclosureAccepted = PreferencesNotifier.create<bool, bool>("data_disclosure_accepted", false);

  // Counts successful connections so the in-app review prompt can wait until
  // the user has connected enough times to form an opinion (see
  // ConnectionNotifier) rather than firing on the first-ever connection.
  static final successfulConnectionCount = PreferencesNotifier.create<int, int>("successful_connection_count", 0);

  static final actionAtClose = PreferencesNotifier.create<ActionsAtClosing, String>(
    "action_at_close",
    ActionsAtClosing.ask,
    mapFrom: ActionsAtClosing.values.byName,
    mapTo: (value) => value.name,
  );
}

@Riverpod(keepAlive: true)
class DebugModeNotifier extends _$DebugModeNotifier {
  late final _pref = PreferencesEntry(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    key: "debug_mode",
    defaultValue: ref.read(environmentProvider) == Environment.dev,
  );

  @override
  bool build() => _pref.read();

  Future<void> update(bool value) {
    state = value;
    return _pref.write(value);
  }
}
