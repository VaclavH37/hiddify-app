import 'package:flutter/services.dart';

/// The one system-bar style for the whole app, for a theme of [brightness].
///
/// It sets only the icons. The bars are transparent and the app draws behind
/// them on every Android version (MainActivity calls `enableEdgeToEdge`, which
/// Android 15+ forces anyway), with each screen keeping its content clear of
/// them. No colours on purpose: Android 15+ ignores bar colours, and a colour
/// here makes Flutter call the `Window` colour setters Play reports as
/// deprecated. Contrast enforcement stays at the system default, which keeps
/// the system's scrim behind 3-button navigation.
SystemUiOverlayStyle raynSystemBarStyle(Brightness brightness) {
  final icons = brightness == Brightness.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    // Android: the colour of the icons themselves.
    statusBarIconBrightness: icons,
    systemNavigationBarIconBrightness: icons,
    // iOS: the brightness of what sits behind the status bar.
    statusBarBrightness: brightness,
  );
}
