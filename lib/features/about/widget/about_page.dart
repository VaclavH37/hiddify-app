import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/glass_surface.dart';
import 'package:hiddify/core/widget/rayn_notification_bell.dart';
import 'package:hiddify/core/widget/rayn_page_header.dart';
import 'package:hiddify/core/widget/rayn_page_scaffold.dart';
import 'package:hiddify/core/widget/rayn_section_header.dart';
import 'package:hiddify/core/widget/rayn_settings_tile.dart';
import 'package:hiddify/features/settings/widget/sub_page_back_button.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AboutPage extends HookConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final appInfo = ref.watch(appInfoProvider).requireValue;
    final palette = context.rayn;

    final trailing = <Widget>[
      PopupMenuButton(
        icon: Icon(AdaptiveIcon(context).more, color: palette.textPrimary),
        itemBuilder: (context) => [
          PopupMenuItem(
            child: Text(t.common.addToClipboard),
            onTap: () {
              Clipboard.setData(ClipboardData(text: appInfo.format()));
            },
          ),
        ],
      ),
      const RaynNotificationBell(),
    ];

    return RaynPageScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: RaynSpacing.xl),
        children: [
          RaynPageHeader(
            title: t.pages.about.title,
            subtitle: t.pages.about.subtitle,
            leading: const SubPageBackButton(),
            trailing: trailing,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
            child: GlassSurface(
              child: Row(
                children: [
                  Assets.images.logo.image(
                    width: 56,
                    height: 56,
                    color: palette.logoMark,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                  const SizedBox(width: RaynSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.common.appTitle, style: RaynTypography.title.copyWith(color: palette.textPrimary)),
                        const SizedBox(height: RaynSpacing.xs),
                        Text(
                          "${t.common.version} ${appInfo.presentVersion}",
                          style: RaynTypography.caption.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          RaynSectionHeader(t.pages.about.links),
          // Support first: it is what people open this page looking for, and the
          // store listing promises "the support link in the app".
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
            child: RaynSettingsTile(
              leading: FluentIcons.person_support_24_regular,
              title: t.pages.about.support,
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.supportUrl));
              },
            ),
          ),
          const SizedBox(height: RaynSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
            child: RaynSettingsTile(
              leading: FluentIcons.chat_24_regular,
              title: t.pages.about.telegramChannel,
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.telegramChannelUrl));
              },
            ),
          ),
          const SizedBox(height: RaynSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
            child: RaynSettingsTile(
              leading: FluentIcons.document_24_regular,
              title: t.pages.about.termsAndConditions,
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.termsAndConditionsUrl));
              },
            ),
          ),
          const SizedBox(height: RaynSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
            child: RaynSettingsTile(
              leading: FluentIcons.shield_24_regular,
              title: t.pages.about.privacyPolicy,
              trailing: const Icon(FluentIcons.open_24_regular),
              onTap: () async {
                await UriUtils.tryLaunch(Uri.parse(Constants.privacyPolicyUrl));
              },
            ),
          ),
          const SizedBox(height: RaynSpacing.xl),
          // Names the publisher inside the app, not just in the store listing.
          // The year tracks the clock rather than being frozen in a literal that
          // silently goes stale.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RaynSpacing.xl),
            child: Text(
              t.pages.about.copyright(
                year: DateTime.now().year.toString(),
                company: Constants.companyLegalName,
              ),
              textAlign: TextAlign.center,
              style: RaynTypography.caption.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
