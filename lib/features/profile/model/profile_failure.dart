import 'package:dio/dio.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/features/profile/model/account_envelope.dart';
import 'package:hiddify/features/settings/model/config_option_failure.dart';

part 'profile_failure.freezed.dart';

@freezed
sealed class ProfileFailure with _$ProfileFailure, Failure {
  const ProfileFailure._();

  @With<UnexpectedFailure>()
  const factory ProfileFailure.unexpected([Object? error, StackTrace? stackTrace]) = ProfileUnexpectedFailure;

  const factory ProfileFailure.notFound() = ProfileNotFoundFailure;

  @With<ExpectedFailure>()
  const factory ProfileFailure.invalidUrl([String? message]) = ProfileInvalidUrlFailure;

  @With<ExpectedFailure>()
  const factory ProfileFailure.alreadyAuthenticated() = ProfileAlreadyAuthenticatedFailure;

  @With<ExpectedFailure>()
  const factory ProfileFailure.invalidConfig([String? message, ConfigOptionFailure? configOptionFailure]) =
      ProfileInvalidConfigFailure;

  @With<ExpectedFailure>()
  const factory ProfileFailure.cancelByUser([String? message]) = ProfileCancelByUserFailure;

  // The account has lapsed and no renewal is available: the MW's `4010` with no
  // `new-url`, or a `4011` (expired while the token was still valid). Distinct
  // from invalidConfig so the user sees a "please renew" message, not "invalid
  // configs". [details] carries the renewal fields when the backend gave a
  // verdict; null on the legacy envelope.
  @With<ExpectedFailure>()
  const factory ProfileFailure.subscriptionExpired([AccountExpiry? details]) = ProfileSubscriptionExpiredFailure;

  // The MW's `4012`: suspended, closed, deleted, pending, or a code this build
  // has never heard of. Never renewable, so it must not read as "please renew".
  // [retryAfter] marks the temporary ones (see [isTransientVerdict]).
  @With<ExpectedFailure>()
  const factory ProfileFailure.accountUnavailable(String code, [Duration? retryAfter]) =
      ProfileAccountUnavailableFailure;

  /// A 4012 the middleware marks retryable with `retry_after` — or the one
  /// code its first handover named as such, kept as the pre-deploy fallback.
  /// A temporary state, not a verdict: the refresh loop backs off and records
  /// nothing, and the stored config keeps serving.
  bool get isTransientVerdict => switch (this) {
    ProfileAccountUnavailableFailure(:final code, :final retryAfter) =>
      retryAfter != null || AccountEnvelope.isTransientCode(code),
    _ => false,
  };

  /// One line for the log: the kind, plus the single detail that says which
  /// step failed. Never the subscription URL (the credential), a token or a
  /// response body — the refresh loop and the post-purchase import report
  /// failures by reason, and a diagnostics build's log reaches a share sheet.
  String get logSummary => switch (this) {
    ProfileUnexpectedFailure(:final error) => switch (error) {
      DioException(:final response?) => 'HTTP ${response.statusCode ?? "?"}',
      DioException(:final type) => 'transport ${type.name}',
      null => 'unexpected',
      _ => 'unexpected ${error.runtimeType}',
    },
    ProfileNotFoundFailure() => 'profile row not found',
    ProfileInvalidUrlFailure() => 'invalid url',
    ProfileAlreadyAuthenticatedFailure() => 'already signed in',
    ProfileInvalidConfigFailure(:final message, :final configOptionFailure) =>
      'config rejected: ${_clip(message ?? configOptionFailure?.runtimeType.toString() ?? "no reason given")}',
    ProfileCancelByUserFailure() => 'cancelled',
    ProfileSubscriptionExpiredFailure() => 'subscription expired verdict',
    ProfileAccountUnavailableFailure(:final code, :final retryAfter) =>
      'account unavailable ($code${retryAfter == null ? "" : ", retry after ${retryAfter.inSeconds}s"})',
    ProfileUnsupportedLinkVersionFailure() => 'unsupported link version',
    ProfileConfigUnreadableFailure() => 'sealed config unreadable',
  };

  // The cryptolink's version byte is one this build has no handler for. The user
  // needs a newer APP, not a newer link — never collapse this into invalidUrl,
  // which would tell them to re-copy a link that is already correct. See
  // RAYN-LINK-SYMMETRIC-MIGRATION.md §10.
  @With<ExpectedFailure>()
  const factory ProfileFailure.unsupportedLinkVersion() = ProfileUnsupportedLinkVersionFailure;

  // The stored `configs/<id>.enc` could not be sealed or opened: the per-install
  // key is gone (keystore wiped, restored to a new device, portable install
  // moved to another Windows user) or the file is corrupt. Never surfaced by
  // reason — the remedy is always the same, re-fetch the subscription — so the
  // copy asks the user to go online rather than describing a crypto failure.
  @With<ExpectedFailure>()
  const factory ProfileFailure.configUnreadable() = ProfileConfigUnreadableFailure;

  @override
  ({String type, String? message}) present(TranslationsEn t) {
    return switch (this) {
      ProfileUnexpectedFailure() => (type: t.errors.profiles.unexpected, message: null),
      ProfileNotFoundFailure() => (type: t.errors.profiles.notFound, message: null),
      ProfileInvalidUrlFailure(:final message) => (type: t.errors.profiles.invalidUrl, message: message),
      ProfileAlreadyAuthenticatedFailure() => (type: t.auth.alreadySignedIn, message: null),
      ProfileInvalidConfigFailure(:final message, :final configOptionFailure) =>
        configOptionFailure?.present(t) ?? (type: t.errors.profiles.invalidConfig, message: message),
      ProfileCancelByUserFailure(:final message) => (type: t.errors.profiles.canceledByUser, message: message),
      ProfileSubscriptionExpiredFailure() => (type: t.errors.profiles.subscriptionExpired, message: null),
      ProfileAccountUnavailableFailure() => (type: t.errors.profiles.accountUnavailable, message: null),
      ProfileUnsupportedLinkVersionFailure() => (type: t.errors.profiles.unsupportedLinkVersion, message: null),
      ProfileConfigUnreadableFailure() => (type: t.errors.profiles.configUnreadable, message: null),
    };
  }
}

/// The core's parse message names a field path, not a value, but it is
/// unbounded; a log line is not.
String _clip(String message, {int max = 160}) => message.length <= max ? message : '${message.substring(0, max)}…';
