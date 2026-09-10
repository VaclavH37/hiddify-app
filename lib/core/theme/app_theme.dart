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

  /// Brand accent. Used as the seed for the generated [ColorScheme] and forced
  /// onto [ColorScheme.primary] in dark mode so widgets reading the accent
  /// (`theme.colorScheme.primary`) render in this exact hex.
  static const Color brandAccent = Color(0xFFF59E0B);

  /// Primary colour in light mode: a near-black for high contrast on light
  /// surfaces. The amber [brandAccent] still seeds the rest of the palette.
  static const Color lightPrimary = Color(0xFF09090B);

  ThemeData lightTheme(ColorScheme? _) {
    final ColorScheme scheme = ColorScheme.fromSeed(seedColor: brandAccent).copyWith(primary: lightPrimary);
    return _themed(scheme, RaynPalette.light, scaffoldBackground: RaynPalette.light.bgPrimary);
  }

  ThemeData darkTheme(ColorScheme? _) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: brandAccent,
      brightness: Brightness.dark,
    ).copyWith(primary: brandAccent);
    const darkSurface = Color(0xFF09090B);
    return _themed(
      scheme,
      RaynPalette.dark,
      scaffoldBackground: mode.trueBlack ? Colors.black : scheme.surface,
      appBar: const AppBarTheme(backgroundColor: darkSurface),
    );
  }

  /// Component themes, once, from the palette: a dialog, a sheet, a menu, a
  /// switch or a divider looks the same wherever it appears, and no call site
  /// styles one by hand. Surfaces are the same opaque `groupFill` as a card;
  /// the accent is the brand amber; the corners are the app's own.
  ThemeData _themed(ColorScheme scheme, RaynPalette palette, {required Color scaffoldBackground, AppBarTheme? appBar}) {
    final cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.card));
    Color? whenSelected(Set<WidgetState> states, Color color) => states.contains(WidgetState.selected) ? color : null;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: appBar,
      fontFamily: fontFamily,
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
        trackColor: WidgetStateProperty.resolveWith((states) => whenSelected(states, brandAccent)),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) => whenSelected(states, Colors.transparent)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) => whenSelected(states, brandAccent)),
        // Dark on amber reads; white on amber does not.
        checkColor: const WidgetStatePropertyAll(Color(0xFF2A241F)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: brandAccent),
      extensions: <ThemeExtension<dynamic>>{palette},
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    final bool isDark = switch (mode) {
      AppThemeMode.system => sysDark,
      AppThemeMode.light => false,
      AppThemeMode.dark => true,
      AppThemeMode.black => true,
    };
    final def = CupertinoThemeData(brightness: isDark ? Brightness.dark : Brightness.light);

    final defaultMaterialTheme = isDark ? darkTheme(darkColorScheme) : lightTheme(lightColorScheme);
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
