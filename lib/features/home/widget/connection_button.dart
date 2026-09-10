import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/theme/rayn_motion.dart';
import 'package:hiddify/core/theme/rayn_palette.dart';
import 'package:hiddify/core/theme/rayn_spacing.dart';
import 'package:hiddify/core/theme/rayn_typography.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/active/active_proxy_notifier.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// URL-test delays at or above this are the core's "no answer" sentinel.
const int _delayTimeout = 65000;

/// Which brand colour the mark is tinted with. The tint IS the state
/// indicator: the mark ships as one flat silhouette and there is no coloured
/// asset per state, so this enum is the whole vocabulary. Resolved to a
/// [RaynPalette] token at render time, which keeps the tray icons (pre-rendered
/// at those same tokens) from drifting away from the in-app colour.
enum OrbTint { disconnected, connecting, connected, error }

/// Everything the orb needs to draw one connection state.
///
/// Derived by [orbStateFor] from the notifier's value, the URL-test delay and
/// the translations, and nothing else, so the whole state table can be tested
/// without a widget tree.
@immutable
class OrbState {
  const OrbState({
    required this.tint,
    required this.label,
    required this.ring,
    required this.enabled,
    this.dimmed = false,
    this.isConnected = false,
  });

  final OrbTint tint;

  /// Status line under the circle; also the semantics label. Never empty:
  /// every branch of the notifier's value produces one, including the error
  /// and initial-load cases that used to fall through to an empty string.
  final String label;

  /// Indeterminate arc drawn just outside the circle while the tunnel is on
  /// its way up or down. It is the motion cue for the transition: the mark
  /// keeps its amber, so without the ring "connecting" and "connected" would be
  /// the same picture.
  final bool ring;

  /// Whether a tap does anything.
  final bool enabled;

  /// Mark at reduced opacity: only before the first status has arrived.
  final bool dimmed;

  /// Reported to assistive technology as the button's toggle state.
  final bool isConnected;

  @override
  bool operator ==(Object other) =>
      other is OrbState &&
      other.tint == tint &&
      other.label == label &&
      other.ring == ring &&
      other.enabled == enabled &&
      other.dimmed == dimmed &&
      other.isConnected == isConnected;

  @override
  int get hashCode => Object.hash(tint, label, ring, enabled, dimmed, isConnected);

  @override
  String toString() =>
      'OrbState($tint, "$label", ring: $ring, enabled: $enabled, dimmed: $dimmed, connected: $isConnected)';
}

/// The state table. [delay] is the active outbound's URL-test delay, 0 when it
/// has not been measured yet.
///
/// A `Connected` status with no measurement yet still reads "Connecting…" with
/// the ring: the core reports the tunnel up before the first URL test answers,
/// and for the user the connection is not usable until it does. A delay at the
/// timeout sentinel is the opposite case: the tunnel is up and the test has
/// finished, just without an answer, so that is "Connected" and the latency
/// readout says "Timeout" on its own. Before this the orb said "Connecting…"
/// for as long as the test server stayed unreachable.
OrbState orbStateFor(AsyncValue<ConnectionStatus> status, int delay, Translations t) {
  return switch (status) {
    AsyncData(value: Disconnected()) => OrbState(
      tint: OrbTint.disconnected,
      label: t.connection.tapToConnect,
      ring: false,
      enabled: true,
    ),
    AsyncData(value: Connecting()) => OrbState(
      tint: OrbTint.connecting,
      label: t.connection.connecting,
      ring: true,
      enabled: false,
    ),
    AsyncData(value: Connected()) when delay <= 0 => OrbState(
      tint: OrbTint.connecting,
      label: t.connection.connecting,
      ring: true,
      enabled: true,
      isConnected: true,
    ),
    AsyncData(value: Connected()) => OrbState(
      tint: OrbTint.connected,
      label: t.connection.connected,
      ring: false,
      enabled: true,
      isConnected: true,
    ),
    AsyncData(value: Disconnecting()) => OrbState(
      tint: OrbTint.connecting,
      label: t.connection.disconnecting,
      ring: true,
      enabled: false,
    ),
    AsyncError(:final error) => OrbState(
      tint: OrbTint.error,
      label: t.presentShortError(error),
      ring: false,
      enabled: true,
    ),
    // AsyncLoading: the initial status has not arrived. The old fall-through
    // painted this red for a frame, then navy with no label at all.
    _ => OrbState(tint: OrbTint.disconnected, label: t.connection.starting, ring: false, enabled: false, dimmed: true),
  };
}

class ConnectionButton extends HookConsumerWidget {
  const ConnectionButton({super.key});

  /// Diameter of the orb's circle. Public because the home canvas centres on
  /// the circle rather than on this widget's box, which also holds the label.
  static const double diameter = 148;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final connectionStatus = ref.watch(connectionNotifierProvider);
    final delay = ref.watch(activeProxyNotifierProvider.select((value) => value.valueOrNull?.urlTestDelay ?? 0));
    // A timed-out test counts as measured for the state table; see orbStateFor.
    final measuredDelay = delay >= _delayTimeout ? _delayTimeout : delay;
    final state = orbStateFor(connectionStatus, measuredDelay, t);

    Future<void> onTap() async {
      if (!state.enabled) return;
      if (!state.isConnected) {
        // Auth gate guarantees a profile exists by the time the home page is
        // reachable; defensive null guard just no-ops.
        if (ref.read(activeProfileProvider).valueOrNull == null) return;
        if (!await ref.read(dialogNotifierProvider.notifier).showExperimentalFeatureNotice()) return;
      }
      await ref.read(connectionNotifierProvider.notifier).toggleConnection();
    }

    return ConnectionOrb(state: state, onTap: onTap);
  }
}

/// The orb's visual half: the disc with the tinted mark, the ring while a
/// transition is in flight, and the status label under it. Public so it can be
/// laid out in a test without the provider graph behind [ConnectionButton].
class ConnectionOrb extends HookWidget {
  const ConnectionOrb({super.key, required this.state, required this.onTap});

  final OrbState state;
  final VoidCallback onTap;

  /// Inset between the circle's edge and the mark's box.
  ///
  /// The artwork carries ~6% transparent margin per side of its own, so the
  /// visible ensō ring only ever comes out at ~88% of whatever box the image
  /// is given. At the old inset of 12 that put the ring at ~109px inside a
  /// 148px orb and it read as floating in the middle; at 3 it is ~125px, which
  /// sits just inside the edge.
  static const double _markInset = 3;

  /// How far outside the circle the progress ring sits, and its stroke.
  static const double _ringGap = 4;
  static const double _ringStroke = 3;

  /// Widest the status label may grow before wrapping; error text can be a
  /// sentence, and it should read as a caption under the orb, not a banner.
  static const double _labelMaxWidth = 260;

  @override
  Widget build(BuildContext context) {
    final palette = context.rayn;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduce = reduceMotion(context);
    final pressed = useState(false);

    final tint = switch (state.tint) {
      OrbTint.disconnected => palette.stateDisconnected,
      OrbTint.connecting => palette.stateConnecting,
      OrbTint.connected => palette.stateConnected,
      OrbTint.error => palette.stateError,
    };

    const diameter = ConnectionButton.diameter;

    final circle = Semantics(
      button: true,
      enabled: state.enabled,
      toggled: state.isConnected,
      label: state.label,
      child: Container(
        width: diameter,
        height: diameter,
        // A neutral shadow lifts the white disc off the canvas in both
        // themes; the light shadow token is soft enough not to muddy cream.
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Material(
          key: const ValueKey("home_connection_button"),
          color: palette.orbFill,
          // On cream the white disc needs an edge to read as a disc at all.
          shape: CircleBorder(side: isLight ? BorderSide(color: palette.glassBorder) : BorderSide.none),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: state.enabled ? onTap : null,
            onHighlightChanged: (value) => pressed.value = value,
            child: Padding(
              padding: const EdgeInsets.all(_markInset),
              child: AnimatedOpacity(
                opacity: state.dimmed ? 0.4 : 1,
                duration: reduce ? Duration.zero : RaynMotion.medium,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: tint),
                  duration: reduce ? Duration.zero : RaynMotion.medium,
                  builder: (context, value, _) =>
                      Assets.images.logo.image(color: value, colorBlendMode: BlendMode.srcIn),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The ring is a positioned child hanging a few pixels outside the circle,
    // so the Stack still sizes to the circle and the canvas keeps centring on
    // it; the overflow stays well inside the gaps the canvas keeps around the
    // orb. (An OverflowBox was tried first. It sizes itself to the largest
    // size its parent allows, and in the orb's column that is unbounded, so
    // the first time the ring appeared the whole page failed to lay out.)
    const ringOverhang = _ringGap + _ringStroke;
    final ring = Positioned.fill(
      left: -ringOverhang,
      top: -ringOverhang,
      right: -ringOverhang,
      bottom: -ringOverhang,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : RaynMotion.fast,
        child: state.ring
            // Expand to the positioned box: left to itself the indicator
            // takes its 36px minimum and spins inside the mark instead.
            ? SizedBox.expand(
                key: const ValueKey('ring'),
                child: CircularProgressIndicator(
                  // Reduce-motion gets a still, three-quarter arc rather than
                  // a spinning one: still unmistakably "in progress".
                  value: reduce ? 0.75 : null,
                  strokeWidth: _ringStroke,
                  strokeCap: StrokeCap.round,
                  color: tint.withValues(alpha: 0.6),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('no-ring')),
      ),
    );

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: pressed.value && state.enabled ? 0.97 : 1,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [ring, circle]),
          ),
          const SizedBox(height: RaynSpacing.lg),
          ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _labelMaxWidth),
              child: AnimatedSwitcher(
                duration: reduce ? Duration.zero : RaynMotion.fast,
                child: Text(
                  state.label,
                  key: ValueKey(state.label),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: RaynTypography.title.copyWith(color: palette.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
