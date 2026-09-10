import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';

/// One row of a settings list. Lives inside a [RaynSettingsGroup], which
/// draws the surface and the dividers; the row itself is flat.
///
/// Leading icon, title, optional subtitle, optional trailing widget. The
/// trailing slot follows one convention per kind of row, so a list scans:
///
/// - navigate within the app: `Icon(Icons.chevron_right_rounded)`
/// - pick a value: [RaynSettingsValue], the current value with a chevron
/// - toggle: `Switch.adaptive` (see `RaynSwitchTile`)
/// - open something outside the app: `Icon(Icons.open_in_new_rounded)`
/// - do something in place (copy, restore, log out): nothing
///
/// [accentColor] tints the icon and title for destructive rows. The leading
/// icon used to sit in a hairline circle; that was decoration standing in for
/// hierarchy, and it went with the rest of the outlined-everything look.
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

  /// When set, tints both the leading icon and the title: destructive
  /// actions (Logout, Delete account).
  final Color? accentColor;

  /// Rows are at least this tall, so a row without a subtitle still has room
  /// for a finger.
  static const double minHeight = 48;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final titleColor = accentColor ?? palette.textPrimary;
    final iconColor = accentColor ?? palette.textSecondary;

    final content = Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.lg, vertical: RaynSpacing.md),
          child: Row(
            children: [
              if (leading != null) ...[
                Icon(leading, size: 22, color: iconColor),
                const SizedBox(width: RaynSpacing.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: RaynTypography.body.copyWith(color: titleColor),
                      // Safety net for server-driven titles (e.g. the account
                      // display name): truncate rather than wrap onto a second
                      // line if it exceeds the row width.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: RaynTypography.caption.copyWith(color: palette.textMuted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: RaynSpacing.md),
                IconTheme.merge(
                  data: IconThemeData(size: 22, color: palette.textSecondary),
                  child: trailing!,
                ),
              ],
            ],
          ),
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

/// The trailing slot of a picker row: the current value, then a chevron.
class RaynSettingsValue extends StatelessWidget {
  const RaynSettingsValue(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: RaynTypography.body.copyWith(color: palette.textMuted),
          ),
        ),
        const SizedBox(width: RaynSpacing.xs),
        const Icon(Icons.chevron_right_rounded),
      ],
    );
  }
}
