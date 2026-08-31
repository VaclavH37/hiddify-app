import 'dart:convert';
import 'dart:math';

import 'package:dartx/dartx.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile_entity.freezed.dart';
part 'profile_entity.g.dart';

enum ProfileType { remote, local }

@freezed
sealed class ProfileEntity with _$ProfileEntity {
  const ProfileEntity._();

  const factory ProfileEntity.remote({
    required String id,
    required bool active,
    required String name,
    required String url,
    required DateTime lastUpdate,
    ProfileOptions? options,
    SubscriptionInfo? subInfo,
    Map<String, dynamic>? populatedHeaders,
    String? profileOverride,
    UserOverride? userOverride,
    // Original `rayn://import/<token>` captured at import — sensitive,
    // exposed only via Settings → Account → Copy token.
    String? sourceToken,
    // Decrypted https URL from a `fallback-url` response header; used
    // when the primary URL fails after dio's RetryInterceptor exhausts.
    String? fallbackUrl,
    // Raw `rayn://import/<token>` string the fallback header arrived as,
    // persisted alongside `fallbackUrl` for parity with `sourceToken`.
    String? fallbackSourceToken,
  }) = RemoteProfileEntity;

  const factory ProfileEntity.local({
    required String id,
    required bool active,
    required String name,
    required DateTime lastUpdate,
    Map<String, dynamic>? populatedHeaders,
    String? profileOverride,
    UserOverride? userOverride,
  }) = LocalProfileEntity;
}

@freezed
class ProfileOptions with _$ProfileOptions {
  const factory ProfileOptions({@Default(Duration.zero) Duration updateInterval}) = _ProfileOptions;
}

@freezed
class SubscriptionInfo with _$SubscriptionInfo {
  const SubscriptionInfo._();

  const factory SubscriptionInfo({
    required int upload,
    required int download,
    required int total,
    required DateTime expire,
    DateTime? refillDate,
    String? webPageUrl,
    String? supportUrl,
  }) = _SubscriptionInfo;

  bool get isExpired => expire <= DateTime.now();

  int get consumption => upload + download;
  int get remainingBW => total - consumption;
  double get remainingBWratio => (remainingBW / total).clamp(0, 1);

  Duration get remaining => expire.difference(DateTime.now());
  double get remainingRatio => min(remaining.inDays, 30) / 30;

  // `ratio` and `untilRefill` lived here to drive the quota card and the
  // account subtitle. Both are gone; `refillDate` is still parsed and stored
  // but nothing reads it.
}

const int latestUserOverrideVersion = 1;

@freezed
abstract class UserOverride with _$UserOverride {
  const UserOverride._();

  const factory UserOverride({
    @Default(latestUserOverrideVersion) int version,
    String? name,
    @Default(false) bool isAutoUpdateDisable,
    // hours
    int? updateInterval,
    bool? enableWarp,
    bool? enableFragment,
  }) = _UserOverride;

  factory UserOverride.fromJson(Map<String, Object?> json) => _$UserOverrideFromJson(json);

  String toStr() => jsonEncode(toJson());

  static UserOverride? fromStr(String? str) {
    if (str != null) {
      final m = (jsonDecode(str) as Map).cast<String, Object?>();
      return UserOverride.fromJson(_migrate(m));
    }
    return null;
  }

  static Map<String, dynamic> _migrate(Map<String, Object?> json) {
    final version = json['version'] as int? ?? 1;

    if (version < 2) {
      // Migration 1 to 2
    }
    json['version'] = latestUserOverrideVersion;
    return json;
  }
}
