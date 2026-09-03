import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:protobuf/protobuf.dart';

/// Latency reported by a `MARKETING_SCREENSHOTS` build, in milliseconds.
///
/// Two values, because the shots come off two very different machines: a
/// desktop on ethernet claiming the same round trip as a phone on Wi-Fi is the
/// kind of detail that makes a store listing look staged.
///
/// Both sit well inside the delay pill's green band (< 300ms) and well outside
/// its timeout threshold, so the pill, its status dot and the connection
/// button all land in their connected state.
const marketingDelayDesktopMs = 21;

/// Android and iOS share this — the split is desktop versus handset, not
/// Android versus everything.
const marketingDelayMobileMs = 32;

int get marketingDelayMs => PlatformUtils.isDesktop ? marketingDelayDesktopMs : marketingDelayMobileMs;

/// Pins [OutboundInfo.urlTestDelay] when this is a screenshots build.
///
/// Applied once where the core's outbound stream enters the app rather than at
/// each widget, so every surface agrees: the latency pill, the connection
/// button (which reads a missing or timed-out delay as "connecting" and paints
/// itself olive), and the desktop tray tooltip and macOS badge.
///
/// Copies rather than mutating. The message belongs to the gRPC stream and may
/// be handed to other listeners; `rebuild` is not an option either, as it
/// throws on anything not already frozen.
///
/// In a normal build [Constants.marketingScreenshots] is a `const false`, so
/// this is an identity function the tree shaker removes.
OutboundInfo pinDelayForMarketing(OutboundInfo info) {
  if (!Constants.marketingScreenshots) return info;
  return info.deepCopy()..urlTestDelay = marketingDelayMs;
}
