import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/features/proxy/active/marketing_delay.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

void main() {
  group('marketing screenshot delay', () {
    test('is off unless the build asked for it', () {
      // The guard that matters. A shipped build reporting an asserted latency
      // would be a lie told in the UI, so this fails the moment the default
      // flips or someone leaves the dart-define in a release recipe.
      expect(Constants.marketingScreenshots, isFalse);
      expect(Constants.marketingDelayMsOverride, 0);
    });

    test('leaves the core reported delay alone when off', () {
      final info = OutboundInfo(tag: 'EXIT-Tokyo', urlTestDelay: 187);
      expect(identical(pinDelayForMarketing(info), info), isTrue);
      expect(info.urlTestDelay, 187);
    });

    test('falls back to the platform default when the build names no latency', () {
      // Tests run on the dev machine, so this pins the desktop branch. The
      // mobile branch is covered by the band assertions below, which hold for
      // both values.
      expect(marketingDelayMs, marketingDelayDesktopMs);
    });

    test('both defaults read as a healthy connection, not a timeout', () {
      // Ties the pinned numbers to the thresholds the UI actually branches on.
      // Above 65000 the pill says "Timeout" and the connection button falls
      // back to its olive "connected, no usable delay" state; at or below zero
      // it shows a shimmer instead of a number. Either would defeat the point
      // of pinning, and both are a single edit away.
      for (final ms in [marketingDelayDesktopMs, marketingDelayMobileMs]) {
        expect(ms, greaterThan(0), reason: 'zero renders as a loading shimmer');
        expect(ms, lessThan(hubUrlTestTimeout), reason: 'would render as Timeout');
        expect(ms, lessThan(300), reason: 'would not paint the green status dot');
      }
    });
  });
}
