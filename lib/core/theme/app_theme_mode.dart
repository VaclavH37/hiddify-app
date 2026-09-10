import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';

enum AppThemeMode {
  system,
  light,
  dark;

  String present(TranslationsEn t) => switch (this) {
    system => t.pages.settings.general.themeModes.system,
    light => t.pages.settings.general.themeModes.light,
    dark => t.pages.settings.general.themeModes.dark,
  };

  ThemeMode get flutterThemeMode => switch (this) {
    system => ThemeMode.system,
    light => ThemeMode.light,
    dark => ThemeMode.dark,
  };

  /// The stored name, or [system] for nothing or anything unknown. "black"
  /// was a fourth mode that set the scaffold to pure black under pages that
  /// all paint their own background, so it never looked different from dark;
  /// a device that stored it gets dark.
  static AppThemeMode fromPersisted(String? name) => switch (name) {
    'light' => light,
    'dark' || 'black' => dark,
    _ => system,
  };
}
