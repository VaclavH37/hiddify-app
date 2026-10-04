import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/model/environment.dart';

part 'app_info_entity.freezed.dart';

@freezed
class AppInfoEntity with _$AppInfoEntity {
  const AppInfoEntity._();

  const factory AppInfoEntity({
    required String name,
    required String version,
    required String buildNumber,
    required Release release,
    required String operatingSystem,
    required String operatingSystemVersion,
    required Environment environment,
  }) = _AppInfoEntity;

  /// User-Agent for core/API HTTP requests. Deliberately names only this
  /// app: the proxy engine it embeds is not something to advertise on the
  /// wire, and no server keys off it.
  String get userAgent => "RaynVPN/$version ($operatingSystem)";

  /// User-Agent sent on subscription API requests: `Rayn/<version> (<os>)`,
  /// e.g. `Rayn/1.6.1 (ios)`.
  ///
  /// The MW counts installs per platform from the bracketed comment. It uses
  /// the same lowercase names as [userAgent] (`ios`, `android`, `windows`,
  /// `macos`, `linux`), so one parser reads both. The MW accepts any agent
  /// that starts with `Rayn`, and the comment leaves that prefix intact.
  ///
  /// Send the platform and nothing else. Adding the OS version, device model
  /// or locale would make a device easier to single out, and the App Store
  /// privacy answers say the app collects none of them.
  String get subscriptionUserAgent => "Rayn/$version ($operatingSystem)";

  /// The version as About shows it. Just the version: a dev build used to
  /// append the environment name, so a phone read "1.5.2 dev" while desktop
  /// read "1.5.2". The environment is still in [format], which the About
  /// menu copies to the clipboard for a support thread.
  String get presentVersion => version;

  /// formats app info for sharing
  String format() =>
      '''
$name v$version ($buildNumber) [${environment.name}]
${release.name} release
$operatingSystem [$operatingSystemVersion]''';
}
