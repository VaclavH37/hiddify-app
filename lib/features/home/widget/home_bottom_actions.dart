import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/add/widgets/fix_btn.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomeBottomActions extends ConsumerWidget {
  const HomeBottomActions({super.key});

  static const double _buttonHeight = 96;
  static const double _maxWidth = 420;
  static const double _gap = 16;
  static const double _bottomGap = 20;
  static const double _segmentApproxHeight = 52;
  static const double _segmentGap = 12;

  /// Vertical space the connection content should reserve so it isn't
  /// hidden behind the floating bottom-action row.
  static const double reservedHeight =
      _segmentApproxHeight + _segmentGap + _buttonHeight + _bottomGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_gap, 0, _gap, _bottomGap),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<ServiceMode>(
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
                onSelectionChanged: (newSet) =>
                    ref.read(ConfigOptions.serviceMode.notifier).update(newSet.first),
              ),
              const Gap(_segmentGap),
              Row(
                children: [
                  if (!PlatformUtils.isDesktop) ...[
                    FixBtn(
                      key: const ValueKey('home_add_by_qr_code_button'),
                      height: _buttonHeight,
                      title: t.common.scanQr,
                      icon: Icons.qr_code_scanner,
                      onTap: () async {
                        final cr = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
                        if (cr == null) return;
                        await ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
                      },
                    ),
                    const Gap(_gap),
                  ],
                  FixBtn(
                    key: const ValueKey('home_add_from_clipboard_button'),
                    height: _buttonHeight,
                    title: t.common.clipboard,
                    icon: Icons.content_paste,
                    color: accent,
                    onTap: () async {
                      final cr = await Clipboard.getData(Clipboard.kTextPlain).then((v) => v?.text ?? '');
                      await ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
                    },
                  ),
                  const Gap(_gap),
                  FixBtn(
                    key: const ValueKey('home_add_manually_button'),
                    height: _buttonHeight,
                    title: t.common.manually,
                    icon: Icons.add,
                    color: accent,
                    onTap: () => ref
                        .read(bottomSheetsNotifierProvider.notifier)
                        .showAddProfile(initialPage: AddProfilePages.manual),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
