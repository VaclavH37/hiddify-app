import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/notification/rayn_toast.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/widget/rayn_surface.dart';

/// The toast is the app's own surface with a tone-tinted icon; nothing of the
/// library's coloured style survives.
void main() {
  Widget host(Widget child) {
    return MaterialApp(
      theme: ThemeData(brightness: Brightness.dark, extensions: const [RaynPalette.dark]),
      home: Scaffold(body: Center(child: child)),
    );
  }

  Color iconColour(WidgetTester tester, IconData icon) => tester.widget<Icon>(find.byIcon(icon)).color!;

  testWidgets('each type tints its icon from the palette', (tester) async {
    await tester.pumpWidget(host(RaynToast(type: NotificationType.info, message: 'm', onClose: () {})));
    expect(iconColour(tester, Icons.info_outline_rounded), RaynPalette.dark.accentText);

    await tester.pumpWidget(host(RaynToast(type: NotificationType.success, message: 'm', onClose: () {})));
    expect(iconColour(tester, Icons.check_circle_outline_rounded), RaynPalette.dark.success);

    await tester.pumpWidget(host(RaynToast(type: NotificationType.error, message: 'm', onClose: () {})));
    expect(iconColour(tester, Icons.error_outline_rounded), RaynPalette.dark.danger);
  });

  testWidgets('it sits on the elevated surface and the close button fires', (tester) async {
    var closed = 0;
    await tester.pumpWidget(host(RaynToast(type: NotificationType.error, message: 'm', onClose: () => closed++)));

    expect(tester.widget<RaynSurface>(find.byType(RaynSurface)).elevated, isTrue);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(closed, 1);
  });

  testWidgets('the width rule caps at 480 and follows the shorter side', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    double? width;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            width = raynToastWidth(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(width, 360 - 32);

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) {
            width = raynToastWidth(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(width, 480);
  });
}
