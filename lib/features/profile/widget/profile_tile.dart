import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Read-only profile tile shown on the home page. Post auth-gate there's
/// always exactly one profile and no in-app way to switch, so the tile is
/// informational only — actions (refresh, copy token, log out) live in
/// Settings → Account.
class ProfileTile extends HookConsumerWidget {
  const ProfileTile({
    super.key,
    required this.profile,
    this.isMain = false,
    this.margin = EdgeInsets.zero,
    this.color,
  });

  final ProfileEntity profile;

  /// home screen active profile card
  final bool isMain;
  final EdgeInsets margin;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final subInfo = switch (profile) {
      RemoteProfileEntity(:final subInfo) => subInfo,
      _ => null,
    };

    return Card(
      margin: margin,
      shape: RoundedRectangleBorder(
        side: profile.active ? BorderSide(color: theme.colorScheme.outline) : BorderSide.none,
        borderRadius: ProfileTileConst.cardBorderRadius,
      ),
      elevation: profile.active ? 0 : 1,
      color: color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              profile.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
              ),
              semanticsLabel: t.pages.profiles.activeProfileName(name: profile.name),
            ),
            if (subInfo != null) ...[
              const Gap(8),
              RemainingTrafficIndicator(subInfo.ratio),
              const Gap(4),
              ProfileSubscriptionInfo(subInfo),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileSubscriptionInfo extends HookConsumerWidget {
  const ProfileSubscriptionInfo(this.subInfo, {super.key});

  final SubscriptionInfo subInfo;

  (String, Color?) remainingText(TranslationsEn t, ThemeData theme) {
    if (subInfo.isExpired) {
      return (t.components.subscriptionInfo.expired, theme.colorScheme.error);
    } else if (subInfo.ratio >= 1) {
      return (t.components.subscriptionInfo.noTraffic, theme.colorScheme.error);
    } else if (subInfo.remaining.inDays > 365) {
      return (t.components.subscriptionInfo.remainingDuration(duration: "∞"), null);
    } else {
      return (t.components.subscriptionInfo.remainingDuration(duration: subInfo.remaining.inDays), null);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final remaining = remainingText(t, theme);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Flexible(
            child: Text(
              subInfo.total > 10 * 1099511627776 ? "∞ GiB" : subInfo.consumption.sizeOf(subInfo.total),
              semanticsLabel: t.components.subscriptionInfo.remainingTrafficSemanticLabel(
                consumed: subInfo.consumption.sizeGB(),
                total: subInfo.total.sizeGB(),
              ),
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Flexible(
          child: Text(
            remaining.$1,
            style: theme.textTheme.bodySmall?.copyWith(color: remaining.$2),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class NewSiteSubscriptionInfo extends HookConsumerWidget {
  const NewSiteSubscriptionInfo(this.subInfo, {super.key});

  final SubscriptionInfo subInfo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final uri = Uri.parse(subInfo.webPageUrl ?? "");
    var host = uri.host;
    if (["telegram.me", "t.me"].contains(host)) {
      host = "@${uri.path.split("/").last}";
    }
    return InkWell(
      onTap: () => launchUrl(Uri.parse(subInfo.webPageUrl ?? "")),
      child: Column(
        children: [
          const Icon(FluentIcons.globe_person_24_filled, size: 24, color: Colors.blue),
          Text(t.components.subscriptionInfo.profileSite),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(host, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}

class RemainingTrafficIndicator extends StatelessWidget {
  const RemainingTrafficIndicator(this.ratio, {super.key});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(value: ratio, borderRadius: BorderRadius.circular(16), minHeight: 6);
  }
}
