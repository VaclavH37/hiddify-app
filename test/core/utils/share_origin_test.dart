import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/utils/share_origin.dart';

/// share_plus refuses a popover share sheet (iPad, and iPhone on recent iOS)
/// unless its anchor is non-empty and inside the view (upstream c49d6edb).
void main() {
  const phone = Size(390, 844);

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test('$platform: a non-empty anchor in the middle of the screen', () {
      final origin = shareOriginFor(platform, phone)!;
      expect(origin.isEmpty, isFalse);
      expect(origin.center, const Offset(195, 422));
      expect(
        (Offset.zero & phone).contains(origin.topLeft) && (Offset.zero & phone).contains(origin.bottomRight),
        isTrue,
      );
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows, TargetPlatform.linux]) {
    test('$platform: no anchor', () => expect(shareOriginFor(platform, phone), isNull));
  }

  test('no anchor before the screen has a size', () {
    expect(shareOriginFor(TargetPlatform.iOS, null), isNull);
    expect(shareOriginFor(TargetPlatform.iOS, Size.zero), isNull);
  });

  testWidgets('shareOrigin reads the platform and the view it runs in', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final onIos = shareOrigin();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final onAndroid = shareOrigin();
    debugDefaultTargetPlatformOverride = null;

    expect(onIos?.center, const Offset(195, 422));
    expect(onAndroid, isNull);
  });
}
