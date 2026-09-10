import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';

/// WCAG contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final light = la > lb ? la : lb;
  final dark = la > lb ? lb : la;
  return (light + 0.05) / (dark + 0.05);
}

void main() {
  group('one amber', () {
    test('the palette accent is the brand accent in both themes', () {
      expect(RaynPalette.dark.accent, AppTheme.brandAccent);
      expect(RaynPalette.light.accent, AppTheme.brandAccent);
    });

    test('the colour scheme primary is the accent in both themes', () {
      final theme = AppTheme(AppThemeMode.system, 'Geist');
      expect(theme.lightTheme().colorScheme.primary, AppTheme.brandAccent);
      expect(theme.darkTheme().colorScheme.primary, AppTheme.brandAccent);
    });

    test('accent text clears AA on each theme page', () {
      // Body text needs 4.5:1. The brand amber itself is about 2:1 on cream,
      // which is why the light theme carries a darker step of it for text.
      expect(contrast(RaynPalette.light.accentText, RaynPalette.light.bgPrimary), greaterThanOrEqualTo(4.5));
      expect(contrast(RaynPalette.light.accentText, RaynPalette.light.groupFill), greaterThanOrEqualTo(4.5));
      expect(contrast(RaynPalette.dark.accentText, RaynPalette.dark.bgPrimary), greaterThanOrEqualTo(4.5));
      expect(contrast(RaynPalette.dark.accentText, RaynPalette.dark.groupFill), greaterThanOrEqualTo(4.5));
    });

    test('dark text on the accent reads', () {
      expect(contrast(AppTheme.onBrandAccent, AppTheme.brandAccent), greaterThanOrEqualTo(4.5));
    });
  });

  group('text and status colours clear AA on every surface', () {
    // Alpha text colours (the dark theme's secondary and muted) are composited
    // onto the surface first, which is what the eye sees.
    Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

    for (final (name, palette) in [('light', RaynPalette.light), ('dark', RaynPalette.dark)]) {
      test(name, () {
        final surfaces = [palette.bgPrimary, palette.bgSurface, palette.pageBackground, palette.groupFill];
        final texts = {
          'textPrimary': palette.textPrimary,
          'textSecondary': palette.textSecondary,
          'textMuted': palette.textMuted,
          'accentText': palette.accentText,
          'success': palette.success,
          'warning': palette.warning,
          'danger': palette.danger,
        };
        for (final MapEntry(key: label, value: colour) in texts.entries) {
          for (final surface in surfaces) {
            expect(
              contrast(over(colour, surface), surface),
              greaterThanOrEqualTo(4.5),
              reason: '$label on ${surface.toARGB32().toRadixString(16)}',
            );
          }
        }
      });
    }
  });

  group('theme mode', () {
    test('a stored "black" becomes dark; unknown values become system', () {
      expect(AppThemeMode.fromPersisted('black'), AppThemeMode.dark);
      expect(AppThemeMode.fromPersisted('dark'), AppThemeMode.dark);
      expect(AppThemeMode.fromPersisted('light'), AppThemeMode.light);
      expect(AppThemeMode.fromPersisted('system'), AppThemeMode.system);
      expect(AppThemeMode.fromPersisted(null), AppThemeMode.system);
      expect(AppThemeMode.fromPersisted('sepia'), AppThemeMode.system);
    });
  });

  group('page transitions', () {
    test('Apple platforms slide, the rest fade forwards, in both themes', () {
      final theme = AppTheme(AppThemeMode.system, 'Geist');
      for (final data in [theme.lightTheme(), theme.darkTheme()]) {
        final builders = data.pageTransitionsTheme.builders;
        expect(builders[TargetPlatform.iOS], isA<CupertinoPageTransitionsBuilder>());
        expect(builders[TargetPlatform.macOS], isA<CupertinoPageTransitionsBuilder>());
        expect(builders[TargetPlatform.android], isA<FadeForwardsPageTransitionsBuilder>());
        expect(builders[TargetPlatform.windows], isA<FadeForwardsPageTransitionsBuilder>());
        expect(builders[TargetPlatform.linux], isA<FadeForwardsPageTransitionsBuilder>());
      }
    });
  });

  group('text theme', () {
    test('headings and titles are on the Geist scale in both themes', () {
      final theme = AppTheme(AppThemeMode.system, 'Geist');
      for (final data in [theme.lightTheme(), theme.darkTheme()]) {
        expect(data.textTheme.titleLarge!.fontSize, 22);
        expect(data.textTheme.headlineSmall!.fontSize, 22);
        expect(data.textTheme.bodyLarge!.fontSize, 16);
        expect(data.textTheme.titleLarge!.fontFamily, 'Geist');
      }
    });
  });
}
