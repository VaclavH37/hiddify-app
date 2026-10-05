import 'dart:io';

import 'package:hiddify/core/model/environment.dart';

/// Whether this build carries the Windows updater at all. Only
/// `make windows-exe-release` sets it.
///
/// Every use of the updater outside `lib/core/app_update/` sits behind
/// `if (kSelfUpdate && …)`. The value is a compile-time constant, so in every
/// other build (Android, iOS, the Mac App Store, MSIX, the portable ZIP) the
/// compiler drops the updater, its manifest address and its pinned keys
/// entirely: Google Play forbids an app that updates itself outside the store,
/// and the App Store answer says the app has no update-check host.
/// `test/design/design_invariants_test.dart` holds both halves of this.
const kSelfUpdate = bool.fromEnvironment('RAYN_SELF_UPDATE');

/// The runtime half of the gate: an installed Windows build, never the portable
/// one even if someone passed the define to it. Always test [kSelfUpdate]
/// first, so the constant can do its job:
///
///     if (kSelfUpdate && selfUpdatePlatform) …
bool get selfUpdatePlatform => Platform.isWindows && !Environment.isPortable;
