import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/auth/payment/data/rayn_billing.g.dart';
import 'package:intl/intl.dart';

/// Localized plan name for a base-plan id (`monthly` / `quarter` / `annual`,
/// the same ids on both stores).
String planName(Translations t, String basePlanId) {
  switch (basePlanId) {
    case 'monthly':
      return t.auth.payment.monthly;
    case 'quarter':
      return t.auth.payment.quarterly;
    case 'annual':
      return t.auth.payment.annual;
    default:
      return basePlanId;
  }
}

/// Localized "per …" label for a base-plan id.
String periodLabel(Translations t, String basePlanId) {
  switch (basePlanId) {
    case 'quarter':
      return t.auth.payment.perQuarter;
    case 'annual':
      return t.auth.payment.perYear;
    default:
      return t.auth.payment.perMonth;
  }
}

/// Months in an ISO-8601 billing period like P1M / P3M / P1Y (default 1).
int periodMonths(String iso) {
  final years = RegExp(r'(\d+)Y').firstMatch(iso);
  final months = RegExp(r'(\d+)M').firstMatch(iso);
  var total = 0;
  if (years != null) total += int.parse(years.group(1)!) * 12;
  if (months != null) total += int.parse(months.group(1)!);
  return total == 0 ? 1 : total;
}

/// Projected first store renewal date for a transition onto an auto-renewing
/// plan: [from] plus the plan's billing period.
///
/// The trial or current plan ends immediately on switch, with no remaining-time
/// carry-over, so renewal follows the standard cycle from today. That holds on
/// both stores — it is what the backend does to a trial, and Apple cannot
/// transfer remaining web-paid time at all (APPLE-IAP-CLIENT-INTEGRATION.md
/// §6). A display estimate only: the authoritative anchor is set by the store
/// and the backend. Pure; unit-tested.
DateTime projectedRenewal(DateTime from, String billingPeriodIso) {
  return DateTime(from.year, from.month + periodMonths(billingPeriodIso), from.day);
}

/// The currency-formatted per-month equivalent for multi-month plans (null for
/// monthly), computed from the store's own localized price so it's correct in
/// any currency.
String? perMonthEquivalent(RaynOffer offer) {
  final months = periodMonths(offer.billingPeriodIso);
  if (months <= 1) return null;
  final perMonth = offer.priceAmountMicros / 1000000 / months;
  return NumberFormat.simpleCurrency(name: offer.priceCurrencyCode).format(perMonth);
}

/// A single live, tappable pricing tier. Shared by the sign-up payment screen and
/// the web→store plan-transition screen; the latter passes a [footnote]
/// (e.g. the projected next-renewal date).
///
/// The card is the standard surface: opaque, a hairline in light mode only.
/// The one card being purchased carries an amber outline while the store is
/// working; nothing is outlined or "recommended" at rest. "Best value" and
/// "Free trial" are a line of amber text under the plan name, not a chip.
class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.t,
    required this.offer,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.footnote,
  });

  final Translations t;
  final RaynOffer offer;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  /// Optional line rendered beneath the plan name (e.g. "Next renewal ~12 Aug").
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final badge = offer.isTrial
        ? t.auth.payment.freeTrial
        : (offer.basePlanId == 'annual' ? t.auth.payment.bestValue : null);
    final equiv = perMonthEquivalent(offer);
    final side = busy
        ? BorderSide(color: palette.accentText, width: 1.5)
        : (isLight ? BorderSide(color: palette.hairline) : BorderSide.none);
    final captionMuted = RaynTypography.caption.copyWith(color: palette.textMuted);

    return Opacity(
      opacity: enabled || busy ? 1 : 0.4,
      child: Material(
        color: palette.groupFill,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.card), side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(RaynSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        planName(t, offer.basePlanId),
                        style: RaynTypography.body.copyWith(color: palette.textPrimary),
                      ),
                      if (badge != null) ...[
                        const SizedBox(height: RaynSpacing.xs),
                        Text(badge, style: RaynTypography.label.copyWith(color: palette.accentText)),
                      ],
                      if (equiv != null) ...[
                        const SizedBox(height: RaynSpacing.xs),
                        Text(t.auth.payment.perMonthEquiv(price: equiv), style: captionMuted),
                      ],
                      if (footnote != null) ...[
                        const SizedBox(height: RaynSpacing.xs),
                        Text(footnote!, style: captionMuted),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: RaynSpacing.md),
                if (busy)
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(offer.formattedPrice, style: RaynTypography.metric.copyWith(color: palette.textPrimary)),
                      Text(
                        periodLabel(t, offer.basePlanId),
                        style: RaynTypography.caption.copyWith(color: palette.textSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
