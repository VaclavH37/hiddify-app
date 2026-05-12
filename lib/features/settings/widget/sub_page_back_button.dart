import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';

/// Circle-bordered back arrow placed in the leading slot of a
/// [RaynPageHeader] on settings sub-pages. Pops the GoRouter stack back to
/// the parent route (Settings).
class SubPageBackButton extends StatelessWidget {
  const SubPageBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.glassBorder),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed('settings');
            }
          },
          child: Icon(Icons.arrow_back_rounded, size: 18, color: palette.textPrimary),
        ),
      ),
    );
  }
}
