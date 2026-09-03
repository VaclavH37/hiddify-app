import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hiddify/utils/platform_utils.dart';

/// The branded launch screen: the wordmark at the top, the mark at screen
/// centre, both sized to 80% of the screen width.
///
/// Every colour here is fixed rather than palette-derived, because this surface
/// is always black in both themes — the light palette's `textPrimary` would be
/// near-invisible on it. That is also why the wordmark takes explicit colour
/// overrides instead of reading the palette as it does everywhere else.
///
/// **Why this is a Flutter screen and not the native launch screen.** A native
/// launch screen can only centre one image; it cannot position text, and it
/// cannot size anything as a fraction of screen width. So the native screen is
/// configured as flat black (`flutter_native_splash` has no `image`) and this
/// draws the brand instead.
///
/// **Ordering caveat.** `lazyBootstrap` finishes every initialiser *before*
/// calling `runApp`, so the native black screen covers the real startup wait
/// and this appears afterwards. It is therefore additive time, which is why the
/// hold is short and lives in one constant. Showing it *during* init would mean
/// moving `runApp` ahead of the initialisers — a bootstrap change, not a
/// widget one.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  static const Color background = Color(0xFF000000);
  static const Color _rayn = Color(0xFFFAFAFA);
  static const Color _vpn = Color(0xFFA1A1AA);

  /// The mark, in brand amber — the same colour as the app icon, so the icon
  /// the user tapped and the screen that follows it agree.
  static const Color _mark = Color(0xFFF59E0B);

  static const double _widthFactor = 0.8;
  static const double _topInset = 40;

  @override
  Widget build(BuildContext context) {
    final target = MediaQuery.sizeOf(context).width * _widthFactor;
    return ColoredBox(
      color: background,
      child: SafeArea(
        child: Stack(
          children: [
            // Words only: the mark is placed separately at centre, so the
            // wordmark's own inline icon would duplicate it.
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: _topInset),
                child: SizedBox(
                  width: target,
                  // FittedBox scales the fixed WORDMARK.md proportions up to
                  // the target width, so the weights and the -0.025em tracking
                  // stay correct at any screen size.
                  child: const FittedBox(
                    child: RaynWordmark(showIcon: false, raynColor: _rayn, vpnColor: _vpn),
                  ),
                ),
              ),
            ),
            Center(
              child: Assets.images.logo.image(
                width: target,
                height: target,
                color: _mark,
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Holds [SplashPage] over [child] for [hold], then cross-fades it away.
///
/// Mobile only: desktop has no native launch screen to hand off from, so a
/// splash there would be pure added latency.
class SplashGate extends HookWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  /// Additive startup time (see the ordering caveat on [SplashPage]) — kept
  /// deliberately short, and in one place so it is easy to tune or zero.
  static const Duration hold = Duration(milliseconds: 1200);
  static const Duration _fade = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    if (!PlatformUtils.isMobile) return child;

    final showing = useState(true);
    // `gone` drops the splash out of the tree once the fade completes, rather
    // than leaving a full-screen transparent layer painting forever.
    final gone = useState(false);

    useEffect(() {
      final timer = Timer(hold, () => showing.value = false);
      return timer.cancel;
    }, const []);

    if (gone.value) return child;

    return Stack(
      children: [
        child,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: showing.value ? 1 : 0,
            duration: _fade,
            onEnd: () {
              if (!showing.value) gone.value = true;
            },
            child: const SplashPage(),
          ),
        ),
      ],
    );
  }
}
