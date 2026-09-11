import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/theme/rayn_radius.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera view that pops with the first QR payload it reads.
///
/// The camera feed is always dark, so the frame and the close button use
/// fixed white and black rather than the palette: they have to read on a
/// live picture in either theme. The frame is 70% of the shorter screen
/// side, capped so it does not balloon on a tablet.
class QrCodeScannerDialog extends HookConsumerWidget {
  const QrCodeScannerDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.read(translationsProvider).requireValue;

    // MobileScanner calls onDetect once per FRAME while a code is in view, and
    // the callbacks keep arriving after the first pop has closed this route —
    // so every scan raised "GoError: There is nothing to pop" from the second
    // frame onward. Caught by PlatformDispatcher rather than crashing, which is
    // why it survived: an unhandled error on the primary auth path, every time.
    //
    // useRef rather than a local: a local resets on rebuild, and this has to
    // latch for the life of the route.
    final handled = useRef(false);
    final frame = math.min(MediaQuery.sizeOf(context).shortestSide * 0.7, 280.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            MobileScanner(
              placeholderBuilder: (context) => const Center(child: CircularProgressIndicator(color: Colors.white)),
              overlayBuilder: (context, constraints) => Center(
                child: Container(
                  width: frame,
                  height: frame,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(RaynRadius.card),
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                ),
              ),
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(RaynSpacing.xl),
                  child: Text(
                    t.common.msg.permission.denied,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              onDetect: (barcodes) {
                if (handled.value || barcodes.barcodes.isEmpty) return;
                final rawData = barcodes.barcodes.first.rawValue;
                if (rawData == null) return;
                handled.value = true;
                context.pop(rawData);
              },
            ),
            Align(
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: const EdgeInsets.all(RaynSpacing.md),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
