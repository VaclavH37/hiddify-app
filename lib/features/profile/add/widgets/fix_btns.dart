import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FixBtns extends ConsumerWidget {
  const FixBtns({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    if (PlatformUtils.isDesktop) {
      return SizedBox(height: height);
    }
    return Row(
      children: [
        const Gap(AddProfileModalConst.fixBtnsGap),
        FixBtn(
          key: const ValueKey('add_by_qr_code_button'),
          height: height,
          title: t.common.scanQr,
          icon: Icons.qr_code_scanner,
          onTap: () async {
            final cr = await ref.read(dialogNotifierProvider.notifier).showQrScanner();
            if (cr == null) return;
            ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
          },
        ),
        const Gap(AddProfileModalConst.fixBtnsGap),
      ],
    );
  }
}
