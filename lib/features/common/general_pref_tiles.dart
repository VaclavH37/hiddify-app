import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/locale_extensions.dart';
import 'package:hiddify/core/localization/locale_preferences.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/theme_preferences.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LocalePrefTile extends ConsumerWidget {
  const LocalePrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final locale = ref.watch(localePreferencesProvider);
    return RaynSettingsTile(
      leading: Icons.translate_rounded,
      title: t.pages.settings.general.locale,
      trailing: RaynSettingsValue(locale.localeName),
      onTap: () async {
        final selectedLocale = await ref
            .read(dialogNotifierProvider.notifier)
            .showSettingPicker<AppLocale>(
              title: t.pages.settings.general.locale,
              selected: locale,
              onReset: () => ref.read(localePreferencesProvider.notifier).changeLocale(AppLocale.en),
              options: AppLocale.values,
              getTitle: (e) => e.localeName,
            );
        if (selectedLocale != null) {
          await ref.read(localePreferencesProvider.notifier).changeLocale(selectedLocale);
        }
      },
    );
  }
}

class ThemeModePrefTile extends ConsumerWidget {
  const ThemeModePrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final themeMode = ref.watch(themePreferencesProvider);
    return RaynSettingsTile(
      leading: switch (themeMode) {
        AppThemeMode.system => Icons.auto_awesome_rounded,
        AppThemeMode.light => Icons.light_mode_rounded,
        AppThemeMode.dark => Icons.dark_mode_rounded,
        AppThemeMode.black => Icons.contrast_rounded,
      },
      title: t.pages.settings.general.themeMode,
      trailing: RaynSettingsValue(themeMode.present(t)),
      onTap: () async {
        final selectedThemeMode = await ref
            .read(dialogNotifierProvider.notifier)
            .showSettingPicker<AppThemeMode>(
              title: t.pages.settings.general.themeMode,
              selected: themeMode,
              onReset: () => ref.read(themePreferencesProvider.notifier).changeThemeMode(AppThemeMode.system),
              options: AppThemeMode.values,
              getTitle: (e) => e.present(t),
            );
        if (selectedThemeMode != null) {
          await ref.read(themePreferencesProvider.notifier).changeThemeMode(selectedThemeMode);
        }
      },
    );
  }
}

class ClosingPrefTile extends ConsumerWidget {
  const ClosingPrefTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final action = ref.watch(Preferences.actionAtClose);
    return RaynSettingsTile(
      leading: Icons.logout_rounded,
      title: t.pages.settings.general.actionAtClosing,
      trailing: RaynSettingsValue(action.present(t)),
      onTap: () async {
        final selectedAction = await ref.read(dialogNotifierProvider.notifier).showActionAtClosing(selected: action);
        if (selectedAction != null) {
          await ref.read(Preferences.actionAtClose.notifier).update(selectedAction);
        }
      },
    );
  }
}

/// Inline switch row used for `Preferences.<bool>` toggles. Composes a
/// [RaynSettingsTile] with a [Switch] in the trailing slot — the whole row is
/// tappable.
class RaynSwitchTile extends StatelessWidget {
  const RaynSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return RaynSettingsTile(
      leading: icon,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      trailing: Switch.adaptive(value: value, onChanged: enabled ? onChanged : null),
      onTap: enabled ? () => onChanged(!value) : null,
    );
  }
}
