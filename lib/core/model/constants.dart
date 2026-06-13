import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class Constants {
  static const appName = "Rayn VPN";
  static const telegramChannelUrl = "https://t.me/raynlabs";
  static const privacyPolicyUrl = "https://www.raynlabs.io/legal/privacy";
  static const termsAndConditionsUrl = "https://www.raynlabs.io/legal/terms";

  /// Base URL of the account/auth API used by the optional email/password
  /// sign-in path. Overridable per build via `--dart-define=api_base_url=...`.
  /// This host may be unreachable on a censored network — login is only a
  /// convenience for obtaining the `rayn://import/<token>`; token import via
  /// QR/clipboard remains the primary, always-available auth path.
  static const apiBaseUrl = String.fromEnvironment("api_base_url", defaultValue: "https://api.raynlabs.io");

  /// Website landing pages the client points users to for flows that complete
  /// out-of-app (account creation, email verification, payment, support).
  static const accountUrl = "https://www.raynlabs.io/account";
}

const kAnimationDuration = Duration(milliseconds: 250);

abstract class AddProfileModalConst {
  static const fixBtnsGap = 16.0;
  static const fixBtnsGapCount = 4;
  static const fixBtnsItemCount = 3;
  static const navBarGap = 16.0;
  static const navBarBottomGap = 4.0;
  //switch default height
  static const navBarcontentHeight = 32.0;
  static const navBarHeight = navBarGap + navBarBottomGap + navBarcontentHeight;
}

abstract class AlertDialogConst {
  static const minWidth = 280.0;
  static const maxWidth = 560.0;
  static const boxConstraints = BoxConstraints(minWidth: minWidth, maxWidth: maxWidth);
}

abstract class BottomSheetConst {
  static const maxWidth = 456.0;
  static const boxConstraints = BoxConstraints(maxWidth: maxWidth);
  static const borderRadius = BorderRadius.vertical(top: Radius.circular(32));
}

abstract class KeyboardConst {
  static final allArrows = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
  };
  static final horizontalArrows = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight};
  static final verticalArrows = {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown};
  static final select = {LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.tab};
}
