import 'package:hiddify/features/profile/model/account_envelope.dart';
import 'package:meta/meta.dart';

/// The account verdict the last subscription refresh returned, persisted so a
/// relaunch (online or not) still knows the plan has lapsed.
///
/// Written by every refresh outcome and by the in-app renewal, cleared by every
/// persisted config. It is deliberately separate from the profile row: an
/// account-status envelope carries none of the config headers, and folding its
/// fields into `populatedHeaders` would wipe the tier, quota and billing
/// metadata the account UI reads (ACCOUNT-REFRESH-MW-HANDOVER.md §9).
sealed class AccountState {
  const AccountState();

  /// Whether the home page routes a connect attempt to the renewal screen.
  /// A live tunnel is never torn down for this; the backend ends it.
  bool get blocksConnect => this is! AccountActive;

  Map<String, Object?> toJson();

  /// Tolerant: anything unreadable is [AccountActive], so a corrupt blob can
  /// never lock a paying user out.
  static AccountState fromJson(Map<String, Object?> json) {
    final detectedAt = DateTime.tryParse(json['detectedAt'] as String? ?? '');
    if (detectedAt == null) return const AccountActive();
    switch (json['kind']) {
      case 'expired':
        final raw = json['details'];
        final details = raw is Map<String, Object?> ? AccountExpiry.fromJson(raw) : AccountExpiry.none;
        return AccountExpired(details: details, detectedAt: detectedAt);
      case 'unavailable':
        final code = json['code'];
        if (code is! String || code.isEmpty) return const AccountActive();
        return AccountUnavailable(code: code, detectedAt: detectedAt);
      default:
        return const AccountActive();
    }
  }
}

/// The last refresh returned a config (or nothing has been refreshed yet).
@immutable
class AccountActive extends AccountState {
  const AccountActive();

  @override
  Map<String, Object?> toJson() => const {'kind': 'active'};

  @override
  bool operator ==(Object other) => other is AccountActive;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'AccountActive';
}

/// 4010 with no renewal, or 4011: renewable.
@immutable
class AccountExpired extends AccountState {
  const AccountExpired({required this.details, required this.detectedAt});

  final AccountExpiry details;

  /// When the client first learned of it; kept across repeated polls.
  final DateTime detectedAt;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'expired',
    'detectedAt': detectedAt.toUtc().toIso8601String(),
    'details': details.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AccountExpired && other.details == details && other.detectedAt == detectedAt;

  @override
  int get hashCode => Object.hash(details, detectedAt);

  @override
  String toString() => 'AccountExpired($details, since ${detectedAt.toIso8601String()})';
}

/// 4012: suspended, closed, deleted, pending or unknown. Not renewable.
@immutable
class AccountUnavailable extends AccountState {
  const AccountUnavailable({required this.code, required this.detectedAt});

  final String code;
  final DateTime detectedAt;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'unavailable',
    'detectedAt': detectedAt.toUtc().toIso8601String(),
    'code': code,
  };

  @override
  bool operator ==(Object other) => other is AccountUnavailable && other.code == code && other.detectedAt == detectedAt;

  @override
  int get hashCode => Object.hash(code, detectedAt);

  @override
  String toString() => 'AccountUnavailable($code, since ${detectedAt.toIso8601String()})';
}
