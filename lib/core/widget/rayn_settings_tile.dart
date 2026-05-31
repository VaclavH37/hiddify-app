import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// Flat settings row used across Settings and About. Renders a leading icon,
/// title, optional subtitle, optional trailing widget (defaults to a chevron
/// for navigation rows), tap callback, disabled state, and an optional accent
/// color (used by destructive actions like Logout). No surrounding card —
/// rows sit directly on the page background.
class RaynSettingsTile extends StatelessWidget {
  const RaynSettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.accentColor,
  });

  final IconData? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  /// When set, tints both the leading icon and the title — used for
  /// destructive actions (Logout) and warning states.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final titleColor = accentColor ?? palette.textPrimary;
    final iconColor = accentColor ?? palette.textPrimary;
    final disabledOpacity = enabled ? 1.0 : 0.4;

    final content = Opacity(
      opacity: disabledOpacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
        child: Row(
          children: [
            if (leading != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor ?? palette.glassBorder),
                ),
                alignment: Alignment.center,
                child: Icon(leading, size: 18, color: iconColor),
              ),
              const SizedBox(width: RaynSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: RaynTypography.body.copyWith(color: titleColor)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: RaynTypography.caption.copyWith(color: palette.textMuted)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: RaynSpacing.md), trailing!],
          ],
        ),
      ),
    );

    if (onTap == null || !enabled) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}
