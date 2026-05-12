import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/widget/glass_surface.dart';

/// Glass-wrapped notification bell shared by the Home, Settings, Logs, and
/// About pages. Visual stub — the bell action is wired in a follow-up.
class RaynNotificationBell extends StatelessWidget {
  const RaynNotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: EdgeInsets.zero,
      radius: RaynRadius.button,
      child: Semantics(
        button: true,
        label: 'Notifications',
        child: IconButton(
          icon: Icon(Icons.notifications_none_rounded, color: context.rayn.textPrimary),
          tooltip: 'Notifications',
          onPressed: () {
            // TODO(notifications): wire to inbox.
          },
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RaynRadius.button)),
            padding: const EdgeInsets.all(RaynSpacing.sm),
          ),
        ),
      ),
    );
  }
}
