import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class Constants {
  /// Whether this build is allowed to produce diagnostics.
  ///
  /// A debug build always is. A release build only when explicitly asked:
  ///
  ///   make ios-adhoc CHANNEL=prod \
  ///     FF_DART_DEFINES=--build-dart-define=RAYN_DIAGNOSTICS=true
  ///
  /// The dart-define exists because a `kDebugMode`-only gate is unreachable on
  /// the topology that needs it: TestFlight and ad-hoc both reject debug builds
  /// (`get-task-allow`), and with the build host in the cloud there is no USB
  /// path to the device, so every artifact that reaches an iPhone is a release.
  ///
  /// **Never distribute a build with this set.** It re-enables the log file on
  /// mobile, the core's debug flag and `data/box.log` — all of which a shipped
  /// build deliberately does without.
  ///
  /// This is one constant on purpose. The export button, the log file and the
  /// core flag were separate gates, and a build that could export logs while
  /// writing none looked like a working diagnostic and produced seven lines of
  /// bootstrap.
  static const diagnosticsBuild = kDebugMode || bool.fromEnvironment("RAYN_DIAGNOSTICS");

  /// Latency a screenshots build reports, in milliseconds, when the build
  /// names one:
  ///
  ///   flutter build windows --dart-define=MARKETING_DELAY_MS=48
  ///   make android-apk-release MARKETING_DELAY=48
  ///
  /// Zero means unset, which is `int.fromEnvironment`'s own default and is
  /// not a value anyone wants anyway — the UI renders a delay of zero as a
  /// loading shimmer. Unset falls back to the per-platform defaults in
  /// `marketingDelayMs`.
  static const marketingDelayMsOverride = int.fromEnvironment("MARKETING_DELAY_MS");

  /// Whether this build pins the numbers that would otherwise differ between
  /// one screenshot and the next.
  ///
  ///   flutter build windows --dart-define=MARKETING_SCREENSHOTS=true
  ///   make android-apk-release \
  ///     FF_DART_DEFINES=--build-dart-define=MARKETING_SCREENSHOTS=true
  ///
  /// Naming a latency turns it on by itself, so that asking for a specific
  /// number can never be the silent no-op that forgetting the second flag
  /// would otherwise be.
  ///
  /// Store listings are a set of stills that have to read as one session. A
  /// real capture run shows whatever the hub answered in at that instant — a
  /// different latency in every shot, and every so often a timeout that also
  /// drops the connection button back to its "connected, no usable delay"
  /// state. See `pinDelayForMarketing`.
  ///
  /// It also fills the paywall in with placeholder prices when the store
  /// returns no products — the state App Store Connect leaves you in until
  /// the subscriptions are at least "Ready to Submit", which is a problem
  /// because it asks for a screenshot of the paywall before then. See
  /// `pinOffersForMarketing`.
  ///
  /// **Never distribute a build with this set.** The latency it reports is
  /// asserted, not measured, and so are the prices.
  static const marketingScreenshots =
      bool.fromEnvironment("MARKETING_SCREENSHOTS") || marketingDelayMsOverride > 0;

  static const appName = "Rayn VPN";

  /// The legal entity that publishes the app. Shown on the About screen so the
  /// publisher is identifiable from inside the app and not only from the store
  /// listing, and used wherever the company has to be named verbatim.
  static const companyLegalName = "Rayn Labs L.L.C.";
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

  /// Support inbox surfaced when the account API can't be reached (e.g. the
  /// host is packet-filtered) and the user can't recover via their token.
  static const supportEmail = "support@raynlabs.io";

  /// Support page, linked from About. The store listing tells users to reach us
  /// "through the support link in the app", so one has to exist and resolve.
  ///
  /// This page must never expose pricing or a way to pay. If it ever does it
  /// becomes an external purchase surface and would have to be hidden on iOS
  /// like [accountUrl] is — which would break the promise the listing makes.
  static const supportUrl = "https://www.raynlabs.io/support";

  /// Google Play subscription product id (a single product carrying the
  /// monthly / quarter / annual base plans + the `trial` offer). The client
  /// queries Play by this id and the backend reads the authoritative product
  /// from Google — see IAP-CLIENT-INTEGRATION.md.
  static const iapProductId = "rayn_premium";
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
