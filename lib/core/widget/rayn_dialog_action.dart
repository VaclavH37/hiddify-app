import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';

/// An action for an `AlertDialog.adaptive`: a Cupertino action on Apple
/// platforms, where the adaptive dialog is a CupertinoAlertDialog and a
/// Material button looks pasted in, and a text button everywhere else.
///
/// [destructive] colours it in the palette's danger, which clears 4.5:1 on
/// every surface. It replaced a danger-filled button whose charcoal
/// foreground sat on the light theme's red at 2.7:1, and which made red a
/// second filled colour next to the brand amber.
Widget raynDialogAction(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
  bool destructive = false,
}) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return CupertinoDialogAction(isDestructiveAction: destructive, onPressed: onPressed, child: Text(label));
  }
  return TextButton(
    style: destructive ? TextButton.styleFrom(foregroundColor: context.rayn.danger) : null,
    onPressed: onPressed,
    child: Text(label),
  );
}
