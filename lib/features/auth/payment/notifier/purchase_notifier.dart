import 'dart:async';

import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:hiddify/features/auth/payment/model/purchase_state.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'purchase_notifier.g.dart';

/// Play `BillingResponseCode`s the launch result is checked against.
const _kBillingOk = 0;
const _kBillingUserCanceled = 1;

/// Fixed display order of the base plans.
const _planOrder = ['monthly', 'quarter', 'annual'];

/// Reduce Play's raw offers to one per base plan — preferring the trial offer
/// (so eligible users see the free trial) — then order monthly→quarter→annual.
/// Pure; unit-tested.
List<RaynOffer> reducePlayOffers(List<RaynOffer> all) {
  final byPlan = <String, RaynOffer>{};
  for (final offer in all) {
    final existing = byPlan[offer.basePlanId];
    if (existing == null || (offer.isTrial && !existing.isTrial)) {
      byPlan[offer.basePlanId] = offer;
    }
  }
  int orderOf(String basePlanId) {
    final i = _planOrder.indexOf(basePlanId);
    return i == -1 ? _planOrder.length : i;
  }

  return byPlan.values.toList()..sort((a, b) => orderOf(a.basePlanId).compareTo(orderOf(b.basePlanId)));
}

/// Like [reducePlayOffers] but prefers the plain base plan over the trial offer.
/// The web→Google Play transition charges the user immediately (the backend
/// defers the *next* billing anchor by their remaining paid time), so surfacing
/// a "free trial" offer would be misleading — fall back to a trial only if Play
/// returns nothing else for a plan. Pure; unit-tested.
List<RaynOffer> reduceUpgradeOffers(List<RaynOffer> all) {
  final byPlan = <String, RaynOffer>{};
  for (final offer in all) {
    final existing = byPlan[offer.basePlanId];
    if (existing == null || (existing.isTrial && !offer.isTrial)) {
      byPlan[offer.basePlanId] = offer;
    }
  }
  int orderOf(String basePlanId) {
    final i = _planOrder.indexOf(basePlanId);
    return i == -1 ? _planOrder.length : i;
  }

  return byPlan.values.toList()..sort((a, b) => orderOf(a.basePlanId).compareTo(orderOf(b.basePlanId)));
}

/// Drives the payment screen: connects billing, loads the offers, launches a
/// purchase, and turns [IapService.outcomes] into [PurchaseState] transitions.
/// Auto-disposed with the screen (cancels the outcome subscription); the
/// underlying [IapService] is keepAlive.
///
/// [transition] selects the web→Google Play plan-transition variant, which shows
/// base-plan offers (no trial) via [reduceUpgradeOffers]; the default sign-up
/// screen ([transition] == false) prefers the trial via [reducePlayOffers]. The
/// buy/verify/import chain is identical for both.
@riverpod
class PurchaseNotifier extends _$PurchaseNotifier with InfraLogger {
  bool _transition = false;

  @override
  PurchaseState build(bool transition) {
    _transition = transition;
    final sub = ref.watch(iapServiceProvider).outcomes.listen(_onOutcome);
    ref.onDispose(sub.cancel);
    unawaited(_init());
    return PurchaseState.loading;
  }

  IapService get _service => ref.read(iapServiceProvider);

  Future<void> _init() async {
    final conn = await _service.connect();
    if (conn != BillingConnState.connected) {
      state = PurchaseState.unavailable;
      return;
    }
    final raw = await _service.loadOffers();
    final offers = _transition ? reduceUpgradeOffers(raw) : reducePlayOffers(raw);
    state = offers.isEmpty
        ? PurchaseState.unavailable
        : PurchaseState(status: PurchaseStatus.ready, offers: offers);
  }

  /// Launch the Play sheet for [offer]. The purchase result returns via the
  /// outcome stream — only a failure to *open* the sheet is handled here.
  Future<void> buy(RaynOffer offer) async {
    if (state.isBusy) return;
    state = state.copyWith(status: PurchaseStatus.busy, pendingOfferToken: offer.offerToken, outcome: null);

    final result = await _service.buy(offer);
    if (result == null || (result.responseCode != _kBillingOk && result.responseCode != _kBillingUserCanceled)) {
      loggy.warning("launchBillingFlow failed: ${result?.responseCode}");
      state = state.copyWith(status: PurchaseStatus.error, outcome: IapPurchaseOutcome.failed, pendingOfferToken: null);
    } else if (result.responseCode == _kBillingUserCanceled) {
      state = state.copyWith(status: PurchaseStatus.ready, pendingOfferToken: null);
    }
    // OK → leave busy; onPurchasesUpdated drives the next transition.
  }

  /// Re-verify active purchases (restore on reinstall / new device). If nothing
  /// is found, return to idle; otherwise the outcome stream sets the result.
  Future<void> restore() async {
    if (state.isBusy) return;
    state = state.copyWith(status: PurchaseStatus.busy, outcome: null);
    final found = await _service.restore();
    if (!found) {
      state = state.copyWith(status: PurchaseStatus.ready, pendingOfferToken: null);
    }
  }

  /// Retry after an error — re-query offers if we never got them, else idle.
  Future<void> retry() async {
    if (state.offers.isEmpty) {
      state = PurchaseState.loading;
      await _init();
    } else {
      state = state.copyWith(status: PurchaseStatus.ready, outcome: null, pendingOfferToken: null);
    }
  }

  void _onOutcome(IapPurchaseOutcome outcome) {
    switch (outcome) {
      case IapPurchaseOutcome.imported:
        state = state.copyWith(status: PurchaseStatus.success, pendingOfferToken: null);
      case IapPurchaseOutcome.activating:
        // Verify succeeded; provisioning underway → full-screen activating view.
        state = state.copyWith(status: PurchaseStatus.activating, pendingOfferToken: null);
      case IapPurchaseOutcome.pendingPayment:
        state = state.copyWith(status: PurchaseStatus.processing, pendingOfferToken: null);
      case IapPurchaseOutcome.canceled:
        state = state.copyWith(status: PurchaseStatus.ready, pendingOfferToken: null);
      case IapPurchaseOutcome.stillProvisioning:
      case IapPurchaseOutcome.accountMismatch:
      case IapPurchaseOutcome.tokenInUse:
      case IapPurchaseOutcome.ineligible:
      case IapPurchaseOutcome.needsLogin:
      case IapPurchaseOutcome.reauthRequired:
      case IapPurchaseOutcome.rateLimited:
      case IapPurchaseOutcome.unreachable:
      case IapPurchaseOutcome.updateRequired:
      case IapPurchaseOutcome.failed:
        state = state.copyWith(status: PurchaseStatus.error, outcome: outcome, pendingOfferToken: null);
    }
  }
}
