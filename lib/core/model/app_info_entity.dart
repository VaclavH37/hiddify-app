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

  /// User-Agent sent on subscription API requests: `Rayn/<version>`.
  String get subscriptionUserAgent => "Rayn/$version";

  String get presentVersion => environment == Environment.prod ? version : "$version ${environment.name}";

  /// formats app info for sharing
  String format() =>
      '''
$name v$version ($buildNumber) [${environment.name}]
${release.name} release
$operatingSystem [$operatingSystemVersion]''';
}
