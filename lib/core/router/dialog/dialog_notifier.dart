import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/actions_at_closing.dart';
import 'package:hiddify/core/router/dialog/widgets/custom_alert_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/ok_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/setting_input_dialog.dart';
import 'package:hiddify/core/router/dialog/widgets/window_closing_dialog.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/core/widget/rayn_option_list.dart';
import 'package:hiddify/features/common/qr_code_scanner_screen.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dialog_notifier.g.dart';

@Riverpod(keepAlive: true)
class DialogNotifier extends _$DialogNotifier {
  @override
  void build() {}

  Future<T?> _show<T>(Widget child) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    return await Navigator.of(context).push<T>(DialogRoute(context: context, builder: (context) => child));
  }

  /// A picker or a details panel. A bottom sheet on a phone, where that is
  /// the platform's idiom and a thumb can reach it; a small dialog on
  /// desktop, where a sheet sliding up the bottom of a large window is
  /// neither. [builder] gets the context of the route it is in, so
  /// `Navigator.of(that).pop(value)` closes the panel with a result.
  Future<T?> _showPanel<T>(WidgetBuilder builder) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    if (PlatformUtils.isMobile) {
      return showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheetContext) => SingleChildScrollView(child: builder(sheetContext)),
      );
    }
    return _show<T>(
      Builder(
        builder: (dialogContext) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(child: builder(dialogContext)),
          ),
        ),
      ),
    );
  }

  Future<String?> showQrScanner() async {
    return await _show<String?>(const QrCodeScannerDialog());
  }

  Future<void> showOk(String title, String description) async {
    return await _show<void>(OkDialog(title: title, description: description));
  }

  Future<ActionsAtClosing?> showActionAtClosing({required ActionsAtClosing selected}) {
    final t = ref.read(translationsProvider).requireValue;
    return showSettingPicker<ActionsAtClosing>(
      title: t.pages.settings.general.actionAtClosing,
      selected: selected,
      options: ActionsAtClosing.values,
      getTitle: (action) => action.present(t),
    );
  }

  Future<T?> showSettingInput<T>({
    required String title,
    required T initialValue,
    T? Function(String value)? mapTo,
    bool Function(String value)? validator,
    String Function(T value)? valueFormatter,
    List<T>? possibleValues,
    VoidCallback? onReset,
    (String text, VoidCallback)? optionalAction,
    IconData? icon,
    bool digitsOnly = false,
  }) async {
    return await _show<T?>(
      SettingInputDialog(
        title: title,
        initialValue: initialValue,
        mapTo: mapTo,
        validator: validator,
        valueFormatter: valueFormatter,
        possibleValues: possibleValues,
        onReset: onReset,
        optionalAction: optionalAction,
        icon: icon,
        digitsOnly: digitsOnly,
      ),
    );
  }

  /// One of a few values, with the current one checked. There is no reset
  /// action any more: the default is in the list like every other value.
  Future<T?> showSettingPicker<T>({
    required String title,
    required T selected,
    required List<T> options,
    required String Function(T e) getTitle,
  }) async {
    return await _showPanel<T?>(
      (panelContext) => RaynOptionList<T>(
        title: title,
        options: options,
        selected: selected,
        getTitle: getTitle,
        onSelected: (value) => Navigator.of(panelContext).pop(value),
      ),
    );
  }

  Future<void> showWindowClosing() async {
    return await _show<void>(const WindowClosingDialog());
  }

  Future<void> showCustomAlertFromErr(({String type, String? message}) err) async {
    return await _show<void>(CustomAlertDialog.fromErr(err));
  }
}
