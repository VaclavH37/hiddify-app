import 'package:flutter/material.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/rayn_motion.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/features/connection/local_routing/notifier/local_routing_notifier.dart';
import 'package:hiddify/features/connection/local_routing/widget/local_routing_banner.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/home/widget/home_canvas_layout.dart';
import 'package:hiddify/features/home/widget/home_top_bar.dart';
import 'package:hiddify/features/notifications/widget/notification_banner.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/proxy_snapshot_notifier.dart';
import 'package:hiddify/features/proxy/active/selected_location_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the pre-connect location machinery alive regardless of connection
    // state or which sub-screen is visible: the snapshot notifier captures the
    // live proxy group while connected (so the list is available offline), and
    // the selected-location notifier applies a pending pre-connect pick when the
    // tunnel comes up. `listen` (not `watch`) instantiates + keeps them alive
    // without rebuilding the home page on every capture.
    ref.listen(proxySnapshotNotifierProvider, (_, _) {});
    ref.listen(selectedLocationNotifierProvider, (_, _) {});

    final isMobile = Breakpoint(context).isMobile();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.rayn;

    // Orientation, not the mobile breakpoint: a phone held sideways wants the
    // landscape treatment, and a narrow desktop window wants the portrait one.
    final isPortrait = MediaQuery.sizeOf(context).aspectRatio < 1;

    // Four vector backgrounds: one composition per orientation, each graded per
    // theme. `cover` crops to the viewport, and a single landscape master was
    // showing about a fifth of its width on a portrait phone — a slice of one
    // region rather than a world map — so portrait gets art laid out for a 1:2
    // frame (3:2 for desktop, which is what the canvas measures once the
    // navigation rail takes its 240). The light files are graded for a light
    // canvas rather than being the dark art behind an opacity multiplier, so
    // there is no runtime opacity here.
    final background = isPortrait
        ? (isDark ? Assets.images.worldmapBgPortraitDark : Assets.images.worldmapBgPortraitLight)
        : (isDark ? Assets.images.worldmapBgDesktopDark : Assets.images.worldmapBgDesktopLight);

    // The system-bar style comes from the app's root region and, under the
    // app bar, from the theme's appBarTheme.
    return DefaultTextStyle.merge(
      style: TextStyle(color: palette.textPrimary),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: isMobile ? const HomeMobileAppBar() : null,
        body: ColoredBox(
          color: palette.bgPrimary,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The map is ~4,500 draw ops and never changes, so it gets its
              // own layer; without the boundary it would be replayed every
              // frame the connection button animates.
              RepaintBoundary(child: background.svg(fit: BoxFit.cover)),
              _HomeCanvas(isMobile: isMobile),
              // Desktop has no app bar; the bell floats top-right instead.
              if (!isMobile) const HomeTopBarBell(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The banner slot holds one banner at a time. The IP routing warning (Windows)
/// takes it while it is up, since it explains why nothing else works; the
/// newest notification has it otherwise.
class _Banner extends ConsumerWidget {
  const _Banner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issue = ref.watch(localRoutingNotifierProvider);
    if (issue != null && !issue.dismissed) return LocalRoutingBanner(issue: issue);
    return const NotificationBanner();
  }
}

/// The orb, its status readout, the location card and the notification banner,
/// placed by [HomeCanvasLayout]. One widget serves both breakpoints: desktop
/// only narrows the column and reserves a band at the top for the bell.
///
/// The canvas normally fills the body exactly, so nothing scrolls. When the
/// body is shorter than the pieces need (a desktop window dragged to its
/// minimum, a small phone or a split-screen window with a banner showing) the
/// canvas grows to what they measured and scrolls instead of letting the card
/// run under the navigation bar (see [HomeCanvas]).
class _HomeCanvas extends StatelessWidget {
  const _HomeCanvas({required this.isMobile});

  final bool isMobile;

  /// Height assumed below the top inset until the first layout has measured
  /// the pieces: the orb and its label, the card, and the gap and bottom inset
  /// [HomeCanvasLayout] adds.
  static const double _minHeight = 340;

  @override
  Widget build(BuildContext context) {
    // Inside a body that extends behind the app bar, Scaffold widens the top
    // padding to the app bar's full height, so on mobile this is the app bar's
    // bottom edge and on desktop it is the status bar (usually zero). Desktop
    // also keeps the band the top-right bell occupies clear.
    final topInset = MediaQuery.paddingOf(context).top + (isMobile ? 0 : RaynSpacing.lg + kMinInteractiveDimension);
    final reduce = reduceMotion(context);

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 600),
          child: HomeCanvas(
            topInset: topInset,
            orbDiameter: ConnectionButton.diameter,
            minHeight: _minHeight,
            horizontalPadding: RaynSpacing.lg,
            // The banner collapses to nothing when there is no notification;
            // animate the change so the orb glides rather than jumps when one
            // arrives or is dismissed.
            banner: AnimatedSize(
              duration: reduce ? Duration.zero : RaynMotion.standard,
              curve: RaynMotion.standardCurve,
              alignment: Alignment.topCenter,
              child: const _Banner(),
            ),
            orb: const ConnectionButton(),
            card: const ActiveProxyFooter(),
          ),
        ),
      ),
    );
  }
}
