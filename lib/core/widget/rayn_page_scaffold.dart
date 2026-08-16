import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';

/// Shared scaffold for pages that adopt the redesigned Rayn surface
/// (Settings, Logs, About). Provides:
///
/// - A flat background drawn from `palette.pageBackground`, which is one
///   step lighter than the sidebar in both themes (no map background, no
///   AppBar).
/// - The active palette's [textPrimary] as the inherited body-text color, so
///   nested widgets don't have to thread color manually.
/// - A [SafeArea]-wrapped body slot.
///
/// The page header (title + subtitle + trailing actions) is part of [body] —
/// callers prepend a [RaynPageHeader] themselves so the header scrolls with
/// the content, matching the mockup.
class RaynPageScaffold extends StatelessWidget {
  const RaynPageScaffold({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.rayn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: palette.textPrimary),
        child: Scaffold(
          backgroundColor: palette.pageBackground,
          body: SafeArea(child: body),
        ),
      ),
    );
  }
}
