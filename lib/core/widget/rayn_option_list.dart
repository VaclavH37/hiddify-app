import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// The body of every picker: a title and a list of options with a check on
/// the current one. Language, theme, what closing the window does, the log
/// level in a debug build.
///
/// `DialogNotifier.showSettingPicker` presents it as a bottom sheet on a
/// phone and a small dialog on desktop; this widget is only the list, and it
/// reports a tap through [onSelected] so the presenter decides what to pop.
///
/// It replaced an AlertDialog of RadioListTiles. Radios are for forms; a list
/// with a check is what both platforms use to pick one of a few values.
class RaynOptionList<T> extends StatelessWidget {
  const RaynOptionList({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.getTitle,
    required this.onSelected,
  });

  final String title;
  final List<T> options;
  final T selected;
  final String Function(T option) getTitle;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.lg, RaynSpacing.xl, RaynSpacing.sm),
            child: Text(title, style: RaynTypography.title.copyWith(color: palette.textPrimary)),
          ),
          for (final option in options)
            _OptionRow(label: getTitle(option), selected: option == selected, onTap: () => onSelected(option)),
          const SizedBox(height: RaynSpacing.sm),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl, vertical: RaynSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: RaynTypography.body.copyWith(color: palette.textPrimary)),
                ),
                if (selected) ...[
                  const SizedBox(width: RaynSpacing.md),
                  const Icon(Icons.check_rounded, size: 22, color: AppTheme.brandAccent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
