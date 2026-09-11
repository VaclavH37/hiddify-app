import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/widget/rayn_notice.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hiddify/utils/uri_utils.dart';

/// Recovery guidance shown on the login and register forms when the account API
/// host is unreachable — e.g. `api.raynlabs.io` is blocked by a packet filter,
/// so the gated request times out. Rather than failing silently it tells the
/// user to retry, fall back to importing their `rayn://import/<token>` from
/// their account page (the always-available path that needs no API access), or
/// contact support if they can't reach their account.
class AuthUnreachableHelp extends StatelessWidget {
  const AuthUnreachableHelp({super.key, required this.t});

  final Translations t;

  @override
  Widget build(BuildContext context) {
    return RaynNotice(
      tone: RaynNoticeTone.danger,
      icon: Icons.cloud_off_rounded,
      // The account page is an external way to pay, so iOS gets neither the
      // link below nor prose pointing at it — guideline 3.1.1.
      message: PlatformUtils.isIOS ? t.auth.unreachable.bodyApple : t.auth.unreachable.body,
      actions: [
        if (!PlatformUtils.isIOS)
          TextButton.icon(
            onPressed: () => UriUtils.tryLaunch(Uri.parse(Constants.accountUrl)),
            icon: const Icon(Icons.open_in_new_rounded),
            label: Text(t.auth.unreachable.openAccount),
          ),
        TextButton.icon(
          onPressed: () => UriUtils.tryLaunch(Uri(scheme: 'mailto', path: Constants.supportEmail)),
          icon: const Icon(Icons.mail_outline_rounded),
          label: Text(t.auth.unreachable.contactSupport),
        ),
      ],
    );
  }
}
