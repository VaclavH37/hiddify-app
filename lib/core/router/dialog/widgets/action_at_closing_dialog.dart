import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ActionsAtClosingDialog extends HookConsumerWidget {
  const ActionsAtClosingDialog({super.key, required this.selected});
  final ActionsAtClosing selected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return SimpleDialog(
      title: Text(t.pages.settings.general.actionAtClosing),
      // RadioGroup takes one child where SimpleDialog takes a list, so the
      // tiles move into a ListBody — which is what SimpleDialog wraps its
      // own children in anyway, so the layout is unchanged.
      children: [
        RadioGroup<ActionsAtClosing>(
          groupValue: selected,
          onChanged: context.pop,
          child: ListBody(
            children: ActionsAtClosing.values
                .map((e) => RadioListTile<ActionsAtClosing>(title: Text(e.present(t)), value: e))
                .toList(),
          ),
        ),
      ],
    );
  }
}
