import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/bottom_sheets/widgets/auto_apps_selection_modal.dart';
import 'package:hiddify/core/router/go_router/go_router_notifier.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'bottom_sheets_notifier.g.dart';

@riverpod
class BottomSheetsNotifier extends _$BottomSheetsNotifier {
  @override
  void build() {}

  Future<T?> _show<T>({required Widget child, required bool isScrollControlled}) async {
    final context = rootNavKey.currentContext;
    if (context == null) return null;
    return await Navigator.of(context).push<T>(
      ModalBottomSheetRoute(
        constraints: BottomSheetConst.boxConstraints,
        isScrollControlled: isScrollControlled,
        builder: (context) => ClipRRect(
          borderRadius: BottomSheetConst.borderRadius,
          child: Material(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showAutoAppsSelection({required AppProxyMode mode}) async =>
      await _show(isScrollControlled: false, child: AutoAppsSelectionModal(mode: mode));
}
