import 'package:freezed_annotation/freezed_annotation.dart';

part 'notification_dedup_state.freezed.dart';
part 'notification_dedup_state.g.dart';

/// Persistent bookkeeping that lets the evaluator fire each notification only
/// once. Stored as a single JSON blob in SharedPreferences (decoupled from the
/// notifications table, so clearing the inbox never re-fires alerts).
///
/// Scoped to one profile via [profileId]; the monitor resets to a fresh state
/// when the active profile changes.
@freezed
class NotificationDedupState with _$NotificationDedupState {
  const factory NotificationDedupState({
    // The profile these markers belong to. When the active profile changes the
    // monitor discards this state and starts fresh.
    String? profileId,
    // ISO8601 `refillDate` identifying the current quota period; null when the
    // backend omits the header (then resets are detected via a consumption drop).
    String? quotaPeriodKey,
    @Default(false) bool quota80Fired,
    @Default(false) bool quota90Fired,
    @Default(false) bool quota100Fired,
    // Last observed `consumption` (upload+download). Used to detect a quota
    // reset when no `refillDate` is available: usage is monotonic within a
    // period, so a decrease means the period rolled over.
    @Default(0) int lastConsumption,
    // ISO8601 `expire` the current expiry cycle is anchored to. When it changes
    // (subscription extended) the per-day marker is cleared.
    String? expiryAnchorKey,
    // yyyy-MM-dd of the last expiry reminder, so it fires at most once per day.
    String? expiryLastFiredDay,
    // ISO8601 `expire` (== renewal date) for which the Google Play "renews
    // tomorrow" reminder already fired. When the sub renews, `expire` advances,
    // this no longer matches, and the reminder is eligible again next cycle.
    String? renewalFiredAnchor,
  }) = _NotificationDedupState;

  factory NotificationDedupState.fromJson(Map<String, Object?> json) => _$NotificationDedupStateFromJson(json);
}
