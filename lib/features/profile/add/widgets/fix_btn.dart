import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FixBtn extends ConsumerWidget {
  const FixBtn({
    super.key,
    required this.height,
    required this.title,
    required this.icon,
    required this.onTap,
    this.color,
  });

  final double height;
  final String title;
  final IconData icon;
  final GestureTapCallback onTap;

  /// When provided, overrides the icon, text, and border colour. When null,
  /// the icon and text use [ColorScheme.primary] and the border uses
  /// [ColorScheme.outlineVariant].
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isMobile = Breakpoint(context).isMobile();
    final accent = color ?? theme.colorScheme.primary;
    final borderColor = color ?? theme.colorScheme.outlineVariant;
    final borderRadius = BorderRadius.circular(18);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          alignment: Alignment.center,
          height: height,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: isMobile ? 32 : 40, color: accent),
              Gap(isMobile ? 4 : 8),
              Text(
                title,
                style: isMobile
                    ? theme.textTheme.titleSmall!.copyWith(color: accent)
                    : theme.textTheme.titleMedium!.copyWith(color: accent),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
