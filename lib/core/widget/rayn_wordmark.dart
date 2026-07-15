import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/gen/assets.gen.dart';

/// Brand wordmark per WORDMARK.md: `[icon] RAYN VPN` on one row — "RAYN" bold
/// anchoring the mark, "VPN" a smaller muted suffix centered against "RAYN"'s
/// vertical middle. "RAYN"/"VPN" are the fixed product wordmark (not localized
/// copy), so they're literal.
///
/// The two text colors come from the brightness-aware palette (`content` /
/// `content-muted` tokens: [RaynPalette.textPrimary] / [RaynPalette.textMuted]),
/// so the mark stays legible on both themes — every surface it appears on (auth,
/// login, home) uses the theme-derived `bgPrimary`, which is a light cream in
/// light mode, so a fixed near-white "RAYN" would be invisible there.
///
/// Defaults to the standard variant (icon 40 / RAYN 30 / VPN 18 / gap 8). For
/// denser surfaces (e.g. an app bar) pass smaller sizes — keep the four values
/// proportional so the mark doesn't distort. The -0.025em tracking is fixed by
/// the spec. To present it as a large screen hero, use [RaynWordmarkHero] (which
/// scales this to a fraction of the screen width).
class RaynWordmark extends StatelessWidget {
  const RaynWordmark({
    super.key,
    this.iconSize = 40,
    this.wordSize = 30,
    this.suffixSize = 18,
    this.gap = 8,
  });

  final double iconSize;
  final double wordSize;
  final double suffixSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // Brand `content` / `content-muted` from the brightness-aware palette so the
    // mark is legible on both light and dark backgrounds.
    final palette = context.rayn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Assets.images.logo.svg(width: iconSize, height: iconSize),
        SizedBox(width: gap),
        Row(
          mainAxisSize: MainAxisSize.min,
          // "VPN" centers against the vertical middle of "RAYN" (not baseline).
          children: [
            Text(
              'RAYN',
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: wordSize,
                height: 1,
                letterSpacing: wordSize * -0.025, // -0.025em
              ),
            ),
            SizedBox(width: gap),
            Text(
              'VPN',
              style: TextStyle(
                color: palette.textMuted,
                fontWeight: FontWeight.w500,
                fontSize: suffixSize,
                height: 1,
                letterSpacing: suffixSize * -0.025, // -0.025em
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The wordmark presented as a screen hero: horizontally centered and scaled to
/// ~[widthFactor] of the screen width (clamped to the available width so it
/// never overflows on wide screens). Shared by the auth + login screens so the
/// mark has identical size, stylization, and position on both.
class RaynWordmarkHero extends StatelessWidget {
  const RaynWordmarkHero({super.key, this.widthFactor = 0.8});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final target = MediaQuery.sizeOf(context).width * widthFactor;
          final width = target > constraints.maxWidth ? constraints.maxWidth : target;
          return SizedBox(
            width: width,
            child: const FittedBox(child: RaynWordmark()),
          );
        },
      ),
    );
  }
}
