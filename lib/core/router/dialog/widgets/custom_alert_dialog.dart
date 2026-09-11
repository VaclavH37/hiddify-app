import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class CustomAlertDialog extends HookConsumerWidget {
  const CustomAlertDialog({super.key, this.title, required this.message});

  final String? title;
  final String message;

  factory CustomAlertDialog.fromErr(({String type, String? message}) err) =>
      CustomAlertDialog(title: err.message == null ? null : err.type, message: err.message ?? err.type);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // The same cap as the desktop picker dialog; the text follows the app's
    // direction like every other dialog (it used to be pinned left-to-right,
    // which broke the Arabic and Persian layouts).
    return AlertDialog(
      title: title != null ? Text(title!) : null,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(child: Text(message)),
      ),
      actions: [
        TextButton(
          onPressed: () {
            context.pop();
          },
          child: Text(t.common.ok),
        ),
      ],
    );
  }
}
