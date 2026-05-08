import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartx/dartx_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/per_app_proxy/data/selected_data_provider.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_backup.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:installed_apps/index.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'per_app_proxy_notifier.g.dart';

@riverpod
class PerAppProxy extends _$PerAppProxy with AppLogger {
  late final AppProxyMode? _mode;

  @override
  Stream<Map<String, int>> build(AppProxyMode? mode) {
    _mode = mode;
    if (_mode == null) return Stream.value({});
    final appsInfo = InstalledApps.getInstalledApps(false);
    return Stream.fromFuture(appsInfo).asyncExpand((appsInfo) {
      final phonePkgs = appsInfo.map((e) => e.packageName).toSet();
      return ref.watch(appProxyDataSourceProvider).watchFilterForDisplay(phonePkgs: phonePkgs, mode: _mode).map((
        entryList,
      ) {
        return {for (final entry in entryList) entry.pkgName: entry.flags};
      });
    });
  }

  Future<void> updatePkg(String pkg) async {
    loggy.info('Updationg $pkg status');
    await ref.read(appProxyDataSourceProvider).updatePkg(pkg: pkg, mode: _mode!);
  }

  Future<void> clearAll() async {
    loggy.info('Clearing all items');
    await ref.read(appProxyDataSourceProvider).clearAll(mode: _mode!);
  }

  Future<bool> importClipboard() async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final input = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text);
      await _importJson(input!);
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.import.success);
      return true;
    } catch (e, st) {
      loggy.warning("error importing from clipboard", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.import.failure);
      return false;
    }
  }

  Future<bool> importFile() async {
    final t = ref.read(translationsProvider).requireValue;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      final file = File(result!.files.single.path!);
      if (!await file.exists()) throw Exception('File does not exist: path = ${file.path}');
      final bytes = await file.readAsBytes();
      await _importJson(jsonDecode(utf8.decode(bytes)).toString());
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.import.success);
      return true;
    } catch (e, st) {
      loggy.warning("error importing config options from json file", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.import.failure);
      return false;
    }
  }

  Future<bool> exportClipboard() async {
    final t = ref.watch(translationsProvider).requireValue;
    try {
      final json = await _exportJson();
      await Clipboard.setData(ClipboardData(text: json));
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
      return true;
    } on PlatformException {
      ref
          .read(inAppNotificationControllerProvider)
          .showInfoToast(t.common.msg.export.clipboard.contentTooLarge, duration: const Duration(seconds: 5));
      return false;
    } catch (e, st) {
      loggy.warning("error exporting to clipboard", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.export.clipboard.failure);
      return false;
    }
  }

  Future<bool> exportFile() async {
    final t = ref.watch(translationsProvider).requireValue;
    try {
      final json = await _exportJson();
      final bytes = utf8.encode(jsonEncode(json));
      final outputFile = await FilePicker.platform.saveFile(
        fileName: 'per-app proxy.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (outputFile == null) return false;
      if (PlatformUtils.isDesktop) {
        final file = File(outputFile);
        if (file.extension != '.json') return false;
        if (!await file.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.file.success);
      return true;
    } catch (e, st) {
      loggy.warning("error exporting config options to json file", e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.export.file.failure);
      return false;
    }
  }

  Future<void> _importJson(String input) async {
    final backup = PerAppProxyBackup.fromJson((jsonDecode(input) as Map).cast());
    await ref.read(appProxyDataSourceProvider).importPkgs(backup: backup);
  }

  Future<String> _exportJson() async {
    final ds = ref.read(appProxyDataSourceProvider);
    final backup = PerAppProxyBackup(
      include: PerAppProxyBackupMode(
        selected: await ds.getPkgsByFlag(mode: AppProxyMode.include, flag: PkgFlag.userSelection),
        deselected: await ds.getPkgsByFlag(mode: AppProxyMode.include, flag: PkgFlag.forceDeselection),
      ),
      exclude: PerAppProxyBackupMode(
        selected: await ds.getPkgsByFlag(mode: AppProxyMode.exclude, flag: PkgFlag.userSelection),
        deselected: await ds.getPkgsByFlag(mode: AppProxyMode.exclude, flag: PkgFlag.forceDeselection),
      ),
    );
    return const JsonEncoder.withIndent('  ').convert(backup.toJson());
  }
}
