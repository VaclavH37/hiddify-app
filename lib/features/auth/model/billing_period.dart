import 'package:hiddify/core/localization/translations.dart';

/// Maps a `subscription-billing-period` value to the payment screen's plan
/// names. The Worker sends `monthly` / `quarterly` / `annual`; `quarter` is
/// the Play base-plan id and is accepted for the same reason. An unknown value
/// passes through unchanged; null stays null.
String? billingPeriodLabel(Translations t, String? raw) => switch (raw) {
  null => null,
  'monthly' => t.auth.payment.monthly,
  'quarter' || 'quarterly' => t.auth.payment.quarterly,
  'annual' => t.auth.payment.annual,
  _ => raw,
};
