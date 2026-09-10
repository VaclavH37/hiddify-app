import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
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

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.button));
    const buttonMinSize = Size(64, 48);
    const buttonPadding = EdgeInsets.symmetric(horizontal: RaynSpacing.xl);
    final buttonTextStyle = RaynTypography.body.copyWith(fontWeight: FontWeight.w600);

    OutlineInputBorder fieldBorder(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(RaynRadius.button),
      borderSide: BorderSide(color: color, width: width),
    );
    // A field's label and icons: danger while invalid, the text-safe amber
    // while focused, muted while disabled, secondary otherwise.
    Color fieldForeground(Set<WidgetState> states) {
      if (states.contains(WidgetState.error)) return palette.danger;
      if (states.contains(WidgetState.disabled)) return palette.textMuted;
      if (states.contains(WidgetState.focused)) return palette.accentText;
      return palette.textSecondary;
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.bgPrimary,
      fontFamily: fontFamily,
      // Sub-pages move the way the platform's own apps do: the Cupertino
      // slide on Apple platforms, Material's fade-forwards elsewhere. Routes
      // use plain MaterialPages and pick this up; there is no per-route
      // custom transition any more.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      // Every role Material widgets read, on the app's own scale, so a page
      // that mixes RaynTypography with textTheme roles shows one body size.
      // The 14px roles map to `paragraph`. labelSmall stays at 12 rather than
      // Material's 11: 12 is the floor the palette's contrast was tuned for.
      textTheme: TextTheme(
        displayLarge: RaynTypography.display,
        displayMedium: RaynTypography.display,
        displaySmall: RaynTypography.display,
        headlineLarge: RaynTypography.display,
        headlineMedium: RaynTypography.display,
        headlineSmall: RaynTypography.title,
        titleLarge: RaynTypography.title,
        titleMedium: RaynTypography.body,
        titleSmall: RaynTypography.paragraph.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: RaynTypography.body.copyWith(fontWeight: FontWeight.w400),
        bodyMedium: RaynTypography.paragraph,
        bodySmall: RaynTypography.caption,
        labelLarge: RaynTypography.paragraph.copyWith(fontWeight: FontWeight.w500),
        labelMedium: RaynTypography.label,
        labelSmall: RaynTypography.caption.copyWith(fontWeight: FontWeight.w500),
      ).apply(bodyColor: palette.textPrimary, displayColor: palette.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.bgSurface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.textPrimary,
      ),
      // Buttons: one shape and one height for all three families, so the
      // pre-auth forms, the dialogs and the settings sub-pages agree. Filled
      // keeps its colours from the scheme (amber, charcoal text) so a call
      // site can still override the background; outlined carries a muted
      // edge; a text button is the same type one weight lighter. Elevation
      // stays at zero: nothing lifts on hover.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          textStyle: buttonTextStyle,
          iconSize: 20,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accentText,
          side: BorderSide(color: palette.textMuted),
          shape: buttonShape,
          minimumSize: buttonMinSize,
          padding: buttonPadding,
          textStyle: buttonTextStyle,
          iconSize: 20,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.accentText,
          shape: buttonShape,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.md),
          textStyle: RaynTypography.body,
          iconSize: 20,
        ),
      ),
      // Fields: an opaque fill one tone above the page with a hairline edge
      // in both themes (a control needs a boundary even when its fill is a
      // tone up), the text-safe amber as the focus ring (the brand amber is
      // about 2:1 on cream, under the 3:1 a ring needs), danger for errors.
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.disabled) ? palette.groupFill.withValues(alpha: 0.5) : palette.groupFill,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
        border: fieldBorder(palette.hairline),
        enabledBorder: fieldBorder(palette.hairline),
        disabledBorder: fieldBorder(palette.hairline.withValues(alpha: 0.5)),
        focusedBorder: fieldBorder(palette.accentText, width: 1.5),
        errorBorder: fieldBorder(palette.danger),
        focusedErrorBorder: fieldBorder(palette.danger, width: 1.5),
        labelStyle: WidgetStateTextStyle.resolveWith(
          (states) => RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: fieldForeground(states)),
        ),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => RaynTypography.label.copyWith(color: fieldForeground(states)),
        ),
        hintStyle: RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: palette.textMuted),
        helperStyle: RaynTypography.caption.copyWith(color: palette.textMuted),
        helperMaxLines: 2,
        errorStyle: RaynTypography.caption.copyWith(color: palette.danger),
        errorMaxLines: 2,
        prefixIconColor: WidgetStateColor.resolveWith(fieldForeground),
        suffixIconColor: WidgetStateColor.resolveWith(fieldForeground),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.accentText,
        selectionColor: palette.accent.withValues(alpha: 0.3),
        selectionHandleColor: palette.accentText,
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
      dividerTheme: DividerThemeData(color: palette.hairline, thickness: 1, space: 1),
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
