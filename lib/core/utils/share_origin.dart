import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where the share sheet is anchored: a 2-point box in the middle of the
/// screen on iOS and macOS, null elsewhere (nothing else reads it).
///
/// iOS presents the sheet as a popover whenever its presentation controller has
/// one (iPad, and iPhone on recent iOS), and share_plus then refuses to open it
/// without an anchor that is non-empty and inside the view: "sharePositionOrigin:
/// argument must be set". Our shares are not opened from a widget that could
/// anchor them, so the middle of the screen it is.
Rect? shareOrigin() {
  // Through the binding rather than PlatformDispatcher.instance: the same view
  // in the app, and the test's view in a widget test.
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  return shareOriginFor(defaultTargetPlatform, view == null ? null : view.physicalSize / view.devicePixelRatio);
}

/// [shareOrigin] for a [platform] and a [screen] size in logical pixels.
@visibleForTesting
Rect? shareOriginFor(TargetPlatform platform, Size? screen) {
  if (platform != TargetPlatform.iOS && platform != TargetPlatform.macOS) return null;
  if (screen == null || screen.isEmpty) return null;
  return Rect.fromCenter(center: screen.center(Offset.zero), width: 2, height: 2);
}
