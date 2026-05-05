import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AddProfileModal extends HookConsumerWidget {
  const AddProfileModal({super.key, this.url});
  final String? url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(addProfileNotifierProvider).isLoading;
    ref.listen(addProfileNotifierProvider, (previous, next) {
      if (next case AsyncData(value: final _?)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && Navigator.canPop(context)) Navigator.of(context).pop();
        });
      }
    });

    useMemoized(() async {
      await Future.delayed(const Duration(milliseconds: 200));
      if (url != null && context.mounted) {
        if (isLoading) return;
        ref.read(addProfileNotifierProvider.notifier).addClipboard(url!);
      }
    });
    return SafeArea(
      child: isLoading ? const ProfileLoading() : const AddProfileOptions(),
    );
  }
}

class AddProfileOptions extends HookConsumerWidget {
  const AddProfileOptions({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fixBtnsHeight =
            (constraints.maxWidth - AddProfileModalConst.fixBtnsGap * AddProfileModalConst.fixBtnsGapCount) /
            AddProfileModalConst.fixBtnsItemCount;
        final fullHeight = fixBtnsHeight + AddProfileModalConst.navBarHeight + 32;
        final size = fullHeight / constraints.maxHeight;
        return DraggableScrollableSheet(
          initialChildSize: size,
          minChildSize: size,
          maxChildSize: size,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              const Gap(AddProfileModalConst.fixBtnsGap),
              FixBtns(height: fixBtnsHeight),
              const Spacer(),
              const NavBar(),
            ],
          ),
        );
      },
    );
  }
}
