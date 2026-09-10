import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

part 'window_notifier.g.dart';

/// Never narrower than the phone breakpoint (600): below it the shell swaps
/// to the bottom bar and the phone app bar, which is not a layout a desktop
/// window should ever present. 640 tall keeps the orb, its label and the
/// location card on screen without the canvas having to scroll.
const minimumWindowSize = Size(600, 640);
const defaultWindowSize = Size(868, 668);

@Riverpod(keepAlive: true)
class WindowNotifier extends _$WindowNotifier with AppLogger {
  @override
  Future<void> build() async {
    if (!PlatformUtils.isDesktop) return;

    await windowManager.ensureInitialized();
    await initWindowState();
  }

  Future<void> saveWindowState() async {
    if (await windowManager.isMaximized()) {
      await ref.read(Preferences.windowMaximized.notifier).update(true);
    } else {
      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();

      await ref.read(Preferences.windowMaximized.notifier).update(false);
      await ref.read(Preferences.windowSize.notifier).update(size);
      await ref.read(Preferences.windowPosition.notifier).update(position);
    }
  }

  Future<void> initWindowState() async {
    final isMaximized = ref.read(Preferences.windowMaximized);
    loggy.debug("window state. maximized: $isMaximized");
    // A size saved by an earlier build can sit below the floor; the OS would
    // clamp it on the next resize but not necessarily on show.
    final stored = ref.read(Preferences.windowSize);
    final size = Size(
      math.max(stored.width, minimumWindowSize.width),
      math.max(stored.height, minimumWindowSize.height),
    );
    loggy.debug("window state. size: $size");
    final position = ref.read(Preferences.windowPosition);
    final isWindowVisible = position != null && await checkWindowVisibility(position, size);
    loggy.debug("window state. position: ${isWindowVisible ? position : "centered"}");
    final silentStart = ref.read(Preferences.silentStart);
    loggy.debug("window state. silent start: ${silentStart ? "Enabled" : "Disabled"}");

    await windowManager.waitUntilReadyToShow(
      WindowOptions(size: size, center: !isWindowVisible, minimumSize: minimumWindowSize),
    );
    if (isWindowVisible) {
      await windowManager.setPosition(position);
      loggy.debug("restoring window to position: $position");
    } else {
      loggy.debug("no previous position found, centering window");
    }
    if (isMaximized) {
      await windowManager.maximize();
      loggy.debug("restoring window to maximized state");
    }
    if (!silentStart) {
      await ref.read(windowNotifierProvider.notifier).show(focus: false);
      loggy.debug("showing app window on start");
    } else {
      loggy.debug("silent start, remain hidden accessible via tray");
    }
  }

  Future<bool> checkWindowVisibility(Offset windowPos, Size windowSize, {double tolerance = 10.0}) async {
    final Rect windowRect = windowPos & windowSize;

    final displays = await screenRetriever.getAllDisplays();

    for (final display in displays) {
      if (display.visiblePosition == null || display.visibleSize == null) {
        continue;
      }
      final Rect monitorRect = display.visiblePosition! & display.visibleSize!;
      if (windowRect.left >= (monitorRect.left - tolerance) &&
          windowRect.top >= (monitorRect.top - tolerance) &&
          windowRect.right <= (monitorRect.right + tolerance) &&
          windowRect.bottom <= (monitorRect.bottom + tolerance)) {
        return true;
      }
    }
    return false;
  }

  Future<void> show({bool focus = true}) async {
    await windowManager.show();
    if (focus) await windowManager.focus();
    if (Platform.isMacOS) {
      await windowManager.setSkipTaskbar(false);
    }
  }

  Future<void> hide() async {
    await windowManager.hide();
    if (Platform.isMacOS) {
      await windowManager.setSkipTaskbar(true);
    }
  }

  Future<void> showOrHide() async {
    if (await windowManager.isVisible()) {
      await hide();
    } else {
      await show();
    }
  }

  Future<void> exit() async {
    await ref
        .read(connectionNotifierProvider.notifier)
        .abortConnection()
        .timeout(const Duration(seconds: 2))
        .catchError((e) {
          loggy.warning("error aborting connection on quit", e);
        });
    await trayManager.destroy();
    await windowManager.destroy();
  }
}
