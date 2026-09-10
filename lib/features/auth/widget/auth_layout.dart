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
/// - a 48px row for [leading], always reserved, so the wordmark sits at the
///   same height on every screen whether or not there is a back button;
/// - the brand wordmark as a hero at [heroWidthFactor] of the screen width;
/// - an optional centred [title] on the title scale;
/// - [children], stretched, in a scroll view that only scrolls when the
///   content is taller than the viewport, and that brings a focused field
///   above the keyboard;
/// - an optional [footer] pinned below the scroll region, for the disclosure
///   actions that must stay reachable without scrolling.
///
/// Content is capped at [maxWidth], centred on wide windows. There is no
/// app bar: nothing tints on scroll, and a back or close action is just an
/// icon button in the leading slot (`SubPageBackButton(fallback: 'auth')`
/// for the sub-screens).
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

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;

    // A scroll view whose content is at least the viewport tall: a short
    // page sits still, a long one scrolls, and a focused field is brought
    // above the keyboard. (Not a SliverFillRemaining: that asks every child
    // for an intrinsic height, which the hero's LayoutBuilder cannot give.)
    final body = LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              RaynSpacing.xl,
              RaynSpacing.sm,
              RaynSpacing.xl,
              footer == null ? RaynSpacing.xl : RaynSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: leadingRowHeight,
                  child: Align(alignment: AlignmentDirectional.centerStart, child: leading),
                ),
                const SizedBox(height: RaynSpacing.sm),
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
          ),
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
                  Expanded(child: body),
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
