import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/window/notifier/window_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Asked when the desktop window is closed and no choice is remembered.
///
/// The question is about the VPN, not the window. Staying in the tray leaves
/// the tunnel exactly as it is; exiting disconnects. The dialog this replaces
/// ("Hide or exit the application?") named neither consequence, and its text
/// button read "Close" while it quit the app and dropped the connection.
///
/// One sentence says what each choice does, worded for the connection state
/// and for where the platform keeps a background app. Keeping the app running
/// is the amber primary and takes Enter; Escape or a click outside cancels the
/// close. The surface, corners and type come from the dialog theme.
class WindowClosingDialog extends ConsumerStatefulWidget {
  const WindowClosingDialog({super.key});

  @override
  ConsumerState<WindowClosingDialog> createState() => _WindowClosingDialogState();
}

class _WindowClosingDialogState extends ConsumerState<WindowClosingDialog> {
  bool _remember = false;

  Future<void> _settle(ActionsAtClosing choice) async {
    if (_remember) {
      await ref.read(Preferences.actionAtClose.notifier).update(choice);
    }
    final window = ref.read(windowNotifierProvider.notifier);
    if (choice == ActionsAtClosing.exit) {
      await window.exit();
      return;
    }
    if (mounted) Navigator.of(context).pop();
    await window.hide();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final connected = ref.watch(connectionNotifierProvider.select((v) => v.valueOrNull?.isConnected ?? false));

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.xl, RaynSpacing.xl, 0),
      contentPadding: const EdgeInsets.fromLTRB(RaynSpacing.xl, RaynSpacing.md, RaynSpacing.xl, 0),
      actionsPadding: const EdgeInsets.fromLTRB(RaynSpacing.lg, RaynSpacing.sm, RaynSpacing.lg, RaynSpacing.lg),
      title: Text(t.dialogs.windowClosing.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(windowClosingBody(t, connected: connected, menuBar: Platform.isMacOS)),
            const SizedBox(height: RaynSpacing.sm),
            // A list tile rather than a bare checkbox beside a label: the whole
            // row is the target, Space toggles it, and a screen reader hears
            // one checkbox with its label.
            //
            // The gap comes from a ListTileTheme, not from the tile's own
            // `horizontalTitleGap`: CheckboxListTile only gained that parameter
            // in a later Flutter than the iOS build machine runs, and the
            // theme has carried it since long before either.
            ListTileTheme.merge(
              horizontalTitleGap: RaynSpacing.sm,
              child: CheckboxListTile(
                value: _remember,
                onChanged: (value) => setState(() => _remember = value ?? _remember),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                dense: true,
                title: Text(
                  t.dialogs.windowClosing.remember,
                  style: RaynTypography.body.copyWith(fontWeight: FontWeight.w400, color: palette.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => _settle(ActionsAtClosing.exit), child: Text(t.common.exit)),
        FilledButton(
          autofocus: true,
          onPressed: () => _settle(ActionsAtClosing.hide),
          child: Text(t.dialogs.windowClosing.keepRunning),
        ),
      ],
    );
  }
}

/// What each choice does, in one sentence pair. [menuBar] is macOS, where a
/// background app lives in the menu bar; everywhere else it is the system tray.
String windowClosingBody(Translations t, {required bool connected, required bool menuBar}) {
  final copy = t.dialogs.windowClosing;
  if (connected) return menuBar ? copy.connectedMenuBar : copy.connectedTray;
  return menuBar ? copy.idleMenuBar : copy.idleTray;
}
