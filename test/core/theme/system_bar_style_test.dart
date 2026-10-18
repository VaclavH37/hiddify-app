import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/system_bar_style.dart';

/// The app's one system-bar style sets icons only. A colour here would make
/// Flutter call the `Window` colour setters Play reports as deprecated, and
/// would paint an opaque bar on Android 14 and older; the bars are transparent
/// on every version (MainActivity calls `enableEdgeToEdge`).
void main() {
  test('dark theme: light icons, and iOS is told the content behind is dark', () {
    final style = raynSystemBarStyle(Brightness.dark);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });

  test('light theme: dark icons, and iOS is told the content behind is light', () {
    final style = raynSystemBarStyle(Brightness.light);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
  });

  for (final brightness in Brightness.values) {
    test('${brightness.name} theme: no bar colours, contrast left to the system', () {
      final style = raynSystemBarStyle(brightness);
      expect(style.statusBarColor, isNull);
      expect(style.systemNavigationBarColor, isNull);
      expect(style.systemNavigationBarDividerColor, isNull);
      expect(style.systemStatusBarContrastEnforced, isNull);
      expect(style.systemNavigationBarContrastEnforced, isNull);
    });
  }
}
