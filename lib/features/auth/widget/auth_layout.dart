import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/core/widget/rayn_wordmark.dart';

/// The one layout behind every screen before sign-in: the landing, login,
/// register, verify-email, the two purchase screens and the disclosures.
///
/// Nine screens used to carry their own copy of the same stack (a transparent
/// app bar on some, none on others, a centred tagline under the hero, three
/// different button heights). This is that stack once:
///
/// - the wordmark hero at [heroWidthFactor] of the screen width, an optional
///   centred [title] on the title scale, and [children], stretched, as one
///   group. When the group is shorter than the screen it sits a little above
///   the middle, the way a sign-in card does; when it is taller it starts
///   under the leading row and scrolls, and a focused field is brought above
///   the keyboard;
/// - [leading] (a back or close icon button) fixed at the top start, outside
///   the scroll region, with its row's height always reserved above the
///   group so the hero can never slide under it;
/// - an optional [footer] pinned below the scroll region, for the disclosure
///   actions that must stay reachable without scrolling.
///
/// Content is capped at [maxWidth], centred on wide windows. There is no
/// app bar: nothing tints on scroll.
///
/// [canPop] is passed to a [PopScope]; the disclosures set it false because
/// leaving them must never count as consent.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    this.leading,
    this.heroWidthFactor = 0.8,
    this.title,
    required this.children,
    this.footer,
    this.canPop = true,
  });

  final Widget? leading;
  final double heroWidthFactor;
  final String? title;
  final List<Widget> children;
  final Widget? footer;
  final bool canPop;

  static const double maxWidth = 480;
  static const double leadingRowHeight = 48;

  /// Where a group shorter than the screen sits: 40% of the free space above
  /// it, 60% below. Dead centre reads as low; this is the optical centre.
  static const Alignment groupAlignment = Alignment(0, -0.2);

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;

    final group = Padding(
      padding: EdgeInsets.fromLTRB(
        RaynSpacing.xl,
        RaynSpacing.sm + leadingRowHeight,
        RaynSpacing.xl,
        footer == null ? RaynSpacing.xl : RaynSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RaynWordmarkHero(widthFactor: heroWidthFactor),
          const SizedBox(height: RaynSpacing.xxl),
          if (title != null) ...[
            Text(
              title!,
              style: RaynTypography.title.copyWith(color: palette.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RaynSpacing.lg),
          ],
          ...children,
        ],
      ),
    );

    // A scroll view whose content is at least the viewport tall. Inside it
    // the group is aligned within that height, so a short group is placed
    // and a tall one simply fills and scrolls. (Not a SliverFillRemaining or
    // an IntrinsicHeight: both ask every child for an intrinsic height,
    // which the hero's LayoutBuilder cannot give.)
    final body = LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Align(alignment: groupAlignment, child: group),
        ),
      ),
    );

    return PopScope(
      canPop: canPop,
      child: Scaffold(
        backgroundColor: palette.bgPrimary,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        body,
                        if (leading != null)
                          PositionedDirectional(top: RaynSpacing.sm, start: RaynSpacing.xl, child: leading!),
                      ],
                    ),
                  ),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(RaynSpacing.xl, 0, RaynSpacing.xl, RaynSpacing.xl),
                      child: footer,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
