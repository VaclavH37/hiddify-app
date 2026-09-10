import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';

/// Back arrow in the leading slot of a [RaynPageHeader] on a sub-page. Pops
/// the router stack; when there is nothing to pop (a cold deep link, or a
/// desktop branch), goes to [fallback] instead.
///
/// [fallback] defaults to Home because the location picker and the inbox are
/// children of the home branch. About passes Settings.
class SubPageBackButton extends StatelessWidget {
  const SubPageBackButton({super.key, this.fallback = 'home'});

  final String fallback;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back_rounded, color: context.rayn.textPrimary),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.goNamed(fallback);
        }
      },
    );
  }
}
