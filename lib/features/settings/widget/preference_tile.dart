import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/settings/notifier/battery_optimization/battery_optimizations_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ValuePreferenceWidget<T> extends HookConsumerWidget {
  const ValuePreferenceWidget({
    super.key,
    required this.value,
    required this.preferences,
    this.enabled = true,
    required this.title,
    this.presentValue,
    this.formatInputValue,
    this.validateInput,
    this.inputToValue,
    this.digitsOnly = false,
    this.icon,
  });

  final T value;
  final PreferencesNotifier<T, dynamic> preferences;
  final bool enabled;
  final String title;
  final String Function(T value)? presentValue;
  final String Function(T value)? formatInputValue;
  final bool Function(String value)? validateInput;
  final T? Function(String input)? inputToValue;
  final bool digitsOnly;
  final IconData? icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RaynSettingsTile(
      leading: icon,
      title: title,
      enabled: enabled,
      trailing: RaynSettingsValue(presentValue?.call(value) ?? value.toString()),
      onTap: () async {
        final inputValue = await ref
            .read(dialogNotifierProvider.notifier)
            .showSettingInput(
              title: title,
              initialValue: value,
              validator: validateInput,
              valueFormatter: formatInputValue,
              onReset: preferences.reset,
              digitsOnly: digitsOnly,
              mapTo: inputToValue,
              possibleValues: preferences.possibleValues,
            );
        if (inputValue == null) {
          return;
        }
        await preferences.update(inputValue);
      },
    );
  }
}

class ChoicePreferenceWidget<T> extends HookConsumerWidget {
  const ChoicePreferenceWidget({
    super.key,
    required this.selected,
    required this.preferences,
    this.enabled = true,
    required this.choices,
    required this.title,
    this.icon,
    required this.presentChoice,
    this.validateInput,
    this.onChanged,
  });

  final T selected;
  final PreferencesNotifier<T, dynamic> preferences;
  final bool enabled;
  final List<T> choices;
  final String title;
  final IconData? icon;
  final String Function(T value) presentChoice;
  final bool Function(String value)? validateInput;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RaynSettingsTile(
      leading: icon,
      title: title,
      enabled: enabled,
      trailing: RaynSettingsValue(presentChoice(selected)),
      onTap: () async {
        final selection = await ref
            .read(dialogNotifierProvider.notifier)
            .showSettingPicker<T>(
              title: title,
              selected: selected,
              options: choices,
              getTitle: (e) => presentChoice(e),
            );
        if (selection == null) return;
        final out = await preferences.update(selection);
        onChanged?.call(selection);
        return out;
      },
    );
  }
}

class BatteryOptimizationWidget extends HookConsumerWidget {
  const BatteryOptimizationWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isIgnoringBatteryOptimizations = ref.watch(batteryOptimizationNotifierProvider);

    return isIgnoringBatteryOptimizations.when(
      data: (isIgnored) => isIgnored
          ? const SizedBox.shrink()
          : RaynSettingsTile(
              leading: Icons.battery_saver_rounded,
              title: t.pages.settings.general.ignoreBatteryOptimizations,
              subtitle: t.pages.settings.general.ignoreBatteryOptimizationsMsg,
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                // Explain why before launching the system exemption prompt, so
                // the user gives informed consent rather than being dropped
                // straight onto an opaque "allow?" system dialog.
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog.adaptive(
                    title: Text(t.pages.settings.general.ignoreBatteryOptimizationsDialogTitle),
                    content: Text(t.pages.settings.general.ignoreBatteryOptimizationsDialogBody),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(t.common.cancel)),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(t.common.kContinue),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await ref.read(batteryOptimizationNotifierProvider.notifier).requestToIgnore();
              },
            ),
      error: (_, _) => const SizedBox.shrink(),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
        child: LinearProgressIndicator(),
      ),
    );
  }
}
