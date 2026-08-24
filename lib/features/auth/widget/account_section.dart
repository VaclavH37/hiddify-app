import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/auth/model/payment_provider.dart';
import 'package:hiddify/features/auth/notifier/logout_notifier.dart';
import 'package:hiddify/features/auth/payment/data/iap_service.dart';
import 'package:hiddify/features/profile/model/hub_tier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/utils/date_time_formatter.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Settings → Account block. Three stacked [RaynSettingsTile]s:
/// profile + refresh, Copy-Token (gated on the original token still being on
/// disk), and a destructive Logout. Loading indicator renders below when the
/// logout request is in flight.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final palette = context.rayn;
    final profileAsync = ref.watch(activeProfileProvider);
    final logoutLoading = ref.watch(logoutNotifierProvider).isLoading;

    final profile = profileAsync.valueOrNull;
    if (profile == null) return const SizedBox.shrink();

    final remote = profile is RemoteProfileEntity ? profile : null;
    final sourceToken = remote?.sourceToken;

    // Subscription-management metadata from the MW subscription headers,
    // persisted in populatedHeaders (ProfileParser.allowedProfileHeaders).
    final provider = subscriptionHeader(remote, 'subscription-payment-provider');
    final billingPeriod = subscriptionHeader(remote, 'subscription-billing-period');
    final manageUrl = subscriptionHeader(remote, 'subscription-manage-url');
    final hubTier = hubTierOf(subscriptionHeader(remote, 'subscription-hub-tier'));
    final isStoreManaged = isStoreManagedProvider(provider);
    // Store IAP is a mobile-only surface (the transition purchase, the
    // store-managed subscription centre, Restore). On desktop there is no
    // billing host and the manage deep-link goes nowhere, so these rows are
    // hidden there.
    final showStoreRows = !PlatformUtils.isDesktop;

    final subInfoLine = remote?.subInfo != null
        ? _formatSubInfo(remote!, t, provider: provider, billingPeriod: billingPeriod, hubTier: hubTier)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaynSettingsTile(
            leading: Icons.account_circle_outlined,
            title: profile.name,
            subtitle: subInfoLine,
            trailing: IconButton(
              tooltip: t.pages.profiles.update,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            ),
          ),
          const SizedBox(height: RaynSpacing.sm),
          // Offer converting a plan that does not renew itself — a legacy
          // web-paid one, or a backend trial — to an auto-renewing store
          // subscription. Hidden once the provider is already store-managed:
          // offering a second one there would charge the user twice for the
          // same account, in either direction (Play sub, iOS build, or vice
          // versa), and neither store refunds that on our behalf.
          if (showStoreRows && remote?.subInfo != null && !isStoreManaged) ...[
            RaynSettingsTile(
              leading: Icons.shop_outlined,
              title: PlatformUtils.isIOS ? t.auth.planTransition.settingsRowApple : t.auth.planTransition.settingsRow,
              subtitle: t.auth.planTransition.settingsRowHint,
              enabled: !logoutLoading,
              onTap: () => context.pushNamed('planTransition'),
            ),
            const SizedBox(height: RaynSpacing.sm),
          ],
          RaynSettingsTile(
            leading: Icons.content_copy,
            title: t.auth.copyToken,
            subtitle: sourceToken == null ? t.auth.noTokenStored : null,
            enabled: sourceToken != null && !logoutLoading,
            onTap: sourceToken == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: sourceToken));
                    if (!context.mounted) return;
                    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.auth.tokenCopied);
                  },
          ),
          const SizedBox(height: RaynSpacing.sm),
          // Manage subscription — store subscribers only. It deep-links to that
          // store's subscription centre (the URL comes from the middleware, so
          // Apple's and Google's both flow through unchanged); for any other
          // provider we must NOT link out to the account page, because it
          // exposes external payment options, which both stores forbid.
          if (showStoreRows && isStoreManaged && manageUrl != null) ...[
            RaynSettingsTile(
              leading: Icons.card_membership_outlined,
              title: t.auth.manageSubscription,
              enabled: !logoutLoading,
              onTap: () => UriUtils.tryLaunch(Uri.parse(manageUrl)),
            ),
            const SizedBox(height: RaynSpacing.sm),
          ],
          // Restore purchases — iOS only. App Review tests this explicitly, and
          // the paywall copy of it is unreachable once a profile exists (the
          // router sends /auth/* to /home), so it needs a home in Settings.
          // Silent by design: outcomes go to IapService.outcomes, which has no
          // listener here; a successful restore imports the profile and the
          // account rows refresh themselves.
          if (PlatformUtils.isIOS) ...[
            RaynSettingsTile(
              leading: Icons.restore,
              title: t.auth.restorePurchases,
              subtitle: t.auth.restorePurchasesHint,
              enabled: !logoutLoading,
              onTap: () => unawaited(ref.read(iapServiceProvider).restore()),
            ),
            const SizedBox(height: RaynSpacing.sm),
          ],
          RaynSettingsTile(
            leading: Icons.logout,
            title: t.auth.logout,
            accentColor: palette.danger,
            enabled: !logoutLoading,
            onTap: () => _confirmLogout(context, ref, t),
          ),
          if (logoutLoading)
            const Padding(
              padding: EdgeInsets.only(top: RaynSpacing.sm),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref, Translations t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(t.auth.logoutConfirmTitle),
        content: Text(t.auth.logoutConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.auth.logoutCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.auth.logoutConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(logoutNotifierProvider.notifier).logout();
    }
  }
}

String _formatSubInfo(
  RemoteProfileEntity profile,
  Translations t, {
  String? provider,
  String? billingPeriod,
  HubTier hubTier = HubTier.primary,
}) {
  final sub = profile.subInfo!;
  final consumed = sub.consumption.sizeGB();
  final total = sub.total.sizeGB();
  final isStoreManaged = isStoreManagedProvider(provider);

  // Line 1: used / total quota, plus days-until-reset when the backend
  // supplied `subscription-refill-date` (hidden otherwise).
  var line1 = '$consumed / $total GB';
  final resetDays = sub.untilRefill?.inDays;
  if (resetDays != null && resetDays >= 0) {
    line1 = '$line1 · ${t.components.subscriptionInfo.quotaResetIn(days: resetDays)}';
  }

  // Line 2: absolute date, or "Never" for the infinite sentinel (mirrors the
  // > 365-day infinity convention). For an auto-renewing Google Play plan this
  // is the *renewal* date, so relabel accordingly.
  final expiryValue = sub.remaining.inDays > 365
      ? t.components.subscriptionInfo.planExpiryNever
      : sub.expire.formatDate();
  final line2 = isStoreManaged
      ? t.components.subscriptionInfo.renewDate(date: expiryValue)
      : t.components.subscriptionInfo.planExpiry(date: expiryValue);

  final lines = [line1, if (hubTier == HubTier.standby) t.components.subscriptionInfo.standbyTitle, line2];

  // Line 3 (when the backend sent a billing period): e.g. "Annual · Auto-renew"
  // — auto-renew for Google Play, manual for any other provider.
  if (billingPeriod != null) {
    final renewType = isStoreManaged
        ? t.components.subscriptionInfo.autoRenew
        : t.components.subscriptionInfo.manualRenew;
    lines.add('${_billingPeriodLabel(billingPeriod, t)} · $renewType');
  }

  return lines.join('\n');
}

/// Maps a `subscription-billing-period` value to a localized label, reusing the
/// payment screen's plan names. Unknown values pass through unchanged.
String _billingPeriodLabel(String raw, Translations t) {
  switch (raw) {
    case 'monthly':
      return t.auth.payment.monthly;
    case 'quarter':
      return t.auth.payment.quarterly;
    case 'annual':
      return t.auth.payment.annual;
    default:
      return raw;
  }
}

extension _SizeFmt on int {
  String sizeGB() => (this / (1024 * 1024 * 1024)).toStringAsFixed(2);
}
