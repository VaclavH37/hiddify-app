import 'package:flutter/services.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:loggy/loggy.dart';

final _log = Loggy<InfraLogger>('date_time_settings');

/// Whether this platform has a date and time settings page the app may open.
///
/// iOS has none: Apple offers no public link to Settings > General > Date &
/// Time (only to the app's own page), so the banner gives the steps instead.
bool get canOpenDateTimeSettings => PlatformUtils.isAndroid || PlatformUtils.isWindows;

/// Opens the system's date and time settings. False when nothing opened, in
/// which case the banner's own words are all the user has.
Future<bool> openDateTimeSettings() async {
  try {
    if (PlatformUtils.isAndroid) {
      return await const MethodChannel("com.raynlabs.app/platform").invokeMethod<bool>("open_date_settings") ?? false;
    }
    if (PlatformUtils.isWindows) return await UriUtils.tryLaunch(Uri.parse('ms-settings:dateandtime'));
  } catch (e) {
    _log.warning("could not open the date and time settings", e);
  }
  return false;
}
