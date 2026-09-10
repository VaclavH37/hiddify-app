import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  /// The brand amber, as a compile-time constant for the few sites that need
  /// one. The same value as [RaynPalette.accent]; the palette is the source
  /// for everything that has a context.
  static const Color brandAccent = Color(0xFFF59E0B);

  /// What sits on amber: the dark text colour of the light theme. White on
  /// amber does not read.
  static const Color onBrandAccent = Color(0xFF2A241F);

  ThemeData lightTheme() => _themed(RaynPalette.light, Brightness.light);

  ThemeData darkTheme() => _themed(RaynPalette.dark, Brightness.dark);

  /// One theme, from the palette, for both brightnesses. The colour scheme is
  /// seeded from the brand amber and its primary IS the brand amber in both
  /// themes, so a filled button is the same button on cream as on charcoal;
  /// the light theme used to make it near-black. Text and icons in the accent
  /// read the palette's text-safe amber, which is a darker step on cream.
  ///
  /// The component themes are set here, once, so a dialog, a sheet, a menu, a
  /// switch or a divider looks the same wherever it appears and no call site
  /// styles one by hand.
  ThemeData _themed(RaynPalette palette, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandAccent,
      brightness: brightness,
    ).copyWith(primary: palette.accent, onPrimary: onBrandAccent, error: palette.danger);
    final cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.card));
    Color? whenSelected(Set<WidgetState> states, Color color) => states.contains(WidgetState.selected) ? color : null;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.bgPrimary,
      fontFamily: fontFamily,
      // The roles Material widgets and the auth pages read, on the app's own
      // scale. Body and label sizes stay at Material's defaults: they are the
      // sizes buttons and fields were designed around.
      textTheme: TextTheme(
        displaySmall: RaynTypography.display,
        headlineSmall: RaynTypography.title,
        titleLarge: RaynTypography.title,
        titleMedium: RaynTypography.body,
        bodyLarge: RaynTypography.body.copyWith(fontWeight: FontWeight.w400),
      ).apply(bodyColor: palette.textPrimary, displayColor: palette.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bgSurface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: palette.accentText)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: palette.accentText),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.groupFill,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        titleTextStyle: RaynTypography.title.copyWith(color: palette.textPrimary),
        contentTextStyle: RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: palette.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.groupFill,
        modalBackgroundColor: palette.groupFill,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(RaynRadius.card))),
        showDragHandle: true,
        dragHandleColor: palette.textMuted,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.groupFill,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.group)),
        textStyle: RaynTypography.body.copyWith(color: palette.textPrimary),
      ),
      dividerTheme: DividerThemeData(color: palette.glassBorder, thickness: 1, space: 1),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => whenSelected(states, Colors.white)),
        trackColor: WidgetStateProperty.resolveWith((states) => whenSelected(states, palette.accent)),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) => whenSelected(states, Colors.transparent)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => whenSelected(states, palette.accent)),
        checkColor: const WidgetStatePropertyAll(onBrandAccent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
      extensions: <ThemeExtension<dynamic>>{palette},
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);

    final defaultMaterialTheme = isDark ? darkTheme() : lightTheme();
    return MaterialBasedCupertinoThemeData(
      materialTheme: defaultMaterialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: fontFamily),
          ),
          barBackgroundColor: def.barBackgroundColor,
          scaffoldBackgroundColor: def.scaffoldBackgroundColor,
        ),
      ),
    );
  }
}
