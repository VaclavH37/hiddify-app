import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/gen/translations.g.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The orb's state table, one case per row. These exist because the old switch
/// had holes: an error painted the orb red with no label, the initial load
/// showed no label either, and a timed-out URL test read "Connecting…" for as
/// long as the test server stayed unreachable.
void main() {
  final t = AppLocale.en.buildSync();

  test('disconnected: navy mark, tap to connect, no ring', () {
    expect(
      orbStateFor(const AsyncData(Disconnected()), 0, t),
      OrbState(tint: OrbTint.disconnected, label: t.connection.tapToConnect, ring: false, enabled: true),
    );
  });

  test('connecting: amber mark with the ring, not tappable', () {
    expect(
      orbStateFor(const AsyncData(Connecting()), 0, t),
      OrbState(tint: OrbTint.connecting, label: t.connection.connecting, ring: true, enabled: false),
    );
  });

  test('connected but not yet measured still shows the ring and "connecting"', () {
    final state = orbStateFor(const AsyncData(Connected()), 0, t);
    expect(state.ring, isTrue);
    expect(state.label, t.connection.connecting);
    // The tunnel is up, so a tap disconnects and assistive tech hears "on".
    expect(state.enabled, isTrue);
    expect(state.isConnected, isTrue);
  });

  test('connected with a measurement: no ring, "connected"', () {
    expect(
      orbStateFor(const AsyncData(Connected()), 21, t),
      OrbState(tint: OrbTint.connected, label: t.connection.connected, ring: false, enabled: true, isConnected: true),
    );
  });

  test('a timed-out test is still connected, not connecting forever', () {
    final state = orbStateFor(const AsyncData(Connected()), 65000, t);
    expect(state.ring, isFalse);
    expect(state.label, t.connection.connected);
  });

  test('disconnecting: ring, not tappable', () {
    final state = orbStateFor(const AsyncData(Disconnecting()), 21, t);
    expect(state.ring, isTrue);
    expect(state.enabled, isFalse);
    expect(state.label, t.connection.disconnecting);
  });

  test('an error names itself and stays tappable so the user can retry', () {
    final state = orbStateFor(AsyncError(Exception('boom'), StackTrace.empty), 0, t);
    expect(state.tint, OrbTint.error);
    expect(state.label, isNotEmpty);
    expect(state.label, t.errors.unexpected);
    expect(state.enabled, isTrue);
    expect(state.ring, isFalse);
  });

  test('before the first status the orb is dimmed, labelled and inert', () {
    final state = orbStateFor(const AsyncLoading(), 0, t);
    expect(state.dimmed, isTrue);
    expect(state.label, t.connection.starting);
    expect(state.enabled, isFalse);
    expect(state.ring, isFalse);
  });

  test('every state carries a label', () {
    final states = [
      const AsyncData<ConnectionStatus>(Disconnected()),
      const AsyncData<ConnectionStatus>(Connecting()),
      const AsyncData<ConnectionStatus>(Connected()),
      const AsyncData<ConnectionStatus>(Disconnecting()),
      const AsyncLoading<ConnectionStatus>(),
      AsyncError<ConnectionStatus>(Exception('x'), StackTrace.empty),
    ];
    for (final status in states) {
      for (final delay in [0, 21, 65000]) {
        expect(orbStateFor(status, delay, t).label, isNotEmpty, reason: '$status at $delay ms');
      }
    }
  });
}
