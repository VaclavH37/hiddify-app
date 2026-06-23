import 'package:flutter/material.dart';
import 'package:hiddify/gen/assets.gen.dart';

/// Brand wordmark per WORDMARK.md: `[icon] RAYN VPN` on one row — "RAYN" bold
/// near-white anchoring the mark, "VPN" a smaller muted suffix centered against
/// "RAYN"'s vertical middle. "RAYN"/"VPN" are the fixed product wordmark (not
/// localized copy), so they're literal.
///
/// Defaults to the standard variant (icon 40 / RAYN 30 / VPN 18 / gap 8). For
/// denser surfaces (e.g. an app bar) pass smaller sizes — keep the four values
/// proportional so the mark doesn't distort. Colors and the -0.025em tracking
/// are fixed by the spec and not theme-derived, so the mark renders identically
/// everywhere it appears. To present it as a large screen hero, use
/// [RaynWordmarkHero] (which scales this to a fraction of the screen width).
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

  // Fixed brand colors from WORDMARK.md (global `content` / `content-muted`
  // tokens) — intentionally not theme-derived so the mark stays consistent.
  static const _wordColor = Color(0xFFFAFAFA);
  static const _suffixColor = Color(0xFFA1A1AA);

  @override
  Widget build(BuildContext context) {
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
                color: _wordColor,
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
                color: _suffixColor,
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
