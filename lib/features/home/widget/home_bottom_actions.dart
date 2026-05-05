import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeBottomActions extends ConsumerWidget {
  const HomeBottomActions({super.key});

  static const double _maxWidth = 420;
  static const double _gap = 16;
  static const double _bottomGap = 20;
  static const double _segmentApproxHeight = 52;

  /// Vertical space the connection content should reserve so it isn't
  /// hidden behind the floating bottom-action row.
  static const double reservedHeight = _segmentApproxHeight + _bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_gap, 0, _gap, _bottomGap),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: SegmentedButton<ServiceMode>(
            showSelectedIcon: false,
            segments: ServiceMode.choices
                .map(
                  (e) => ButtonSegment(
                    value: e,
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(e.presentShort(t), textAlign: TextAlign.center),
                    ),
                  ),
                )
                .toList(),
            selected: {ref.watch(ConfigOptions.serviceMode)},
            onSelectionChanged: (newSet) => ref.read(ConfigOptions.serviceMode.notifier).update(newSet.first),
          ),
        ),
      ),
    );
  }
}
