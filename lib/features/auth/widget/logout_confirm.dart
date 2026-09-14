import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/widget/rayn_dialog_action.dart';
import 'package:hiddify/features/auth/notifier/logout_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The one logout confirmation, shared by Settings → Account and the renewal
/// screen. Adaptive dialog; the destructive action is red text, never a fill.
Future<void> confirmLogout(BuildContext context, WidgetRef ref, Translations t) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(t.auth.logoutConfirmTitle),
      content: Text(t.auth.logoutConfirmBody),
      actions: [
        raynDialogAction(ctx, label: t.auth.logoutCancel, onPressed: () => Navigator.of(ctx).pop(false)),
        raynDialogAction(
          ctx,
          label: t.auth.logoutConfirmAction,
          onPressed: () => Navigator.of(ctx).pop(true),
          destructive: true,
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(logoutNotifierProvider.notifier).logout();
  }
}
