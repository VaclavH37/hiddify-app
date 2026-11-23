import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/auth/account/model/account_state.dart';
import 'package:hiddify/features/auth/account/notifier/account_state_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the connect button shows comes from ConnectionNotifier's state, which
/// the core's status stream drives and the notifier itself sets around a
/// connect or disconnect. These run the real notifier against a repository
/// whose status stream and connect/disconnect results the test controls.
void main() {
  late ProviderContainer container;
  late _Repo repo;
  late _Dialogs dialogs;

  ConnectionNotifier notifier() => container.read(connectionNotifierProvider.notifier);
  AsyncValue<ConnectionStatus> state() => container.read(connectionNotifierProvider);

  setUp(() async {
    // Haptics off: they go through a platform channel.
    SharedPreferences.setMockInitialValues({'haptic_feedback': false});
    repo = _Repo();
    dialogs = _Dialogs();
    container = ProviderContainer(
      overrides: [
        connectionRepositoryProvider.overrideWithValue(repo),
        activeProfileProvider.overrideWith(_Profile.new),
        accountStateNotifierProvider.overrideWith(_Account.new),
        dialogNotifierProvider.overrideWith(() => dialogs),
        translationsProvider.overrideWith((ref) async => AppLocale.en.buildSync()),
        sharedPreferencesProvider.overrideWith((ref) => SharedPreferences.getInstance()),
      ],
    );
    await container.read(sharedPreferencesProvider.future);
    await container.read(translationsProvider.future);
    await container.read(activeProfileProvider.future);
    container.listen(connectionNotifierProvider, (_, _) {});
    await container.read(connectionNotifierProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await repo.close();
  });

  test('a tap shows Connecting before the core reports anything', () async {
    expect(state(), const AsyncData<ConnectionStatus>(Disconnected()));

    await notifier().toggleConnection();
    await _until(() => repo.connects == 1);

    // The core has said nothing yet: this is the notifier's own Connecting.
    expect(state(), const AsyncData<ConnectionStatus>(Connecting()));

    repo.connecting!.complete(right(unit));
    repo.report(const Connected());
    await _until(() => state() == const AsyncData<ConnectionStatus>(Connected()));
  });

  test('a second tap while connecting does not start a second connect', () async {
    await notifier().toggleConnection();
    await _until(() => repo.connects == 1);
    await notifier().toggleConnection();
    await _settle();

    expect(repo.connects, 1);
    expect(state(), const AsyncData<ConnectionStatus>(Connecting()));
  });

  test('a failed connect shows its error while the dialog is open', () async {
    dialogs.open = Completer();
    await notifier().toggleConnection();
    await _until(() => repo.connects == 1);
    repo.connecting!.complete(left(const ConnectionFailure.missingVpnPermission()));
    await _until(() => dialogs.shown.isNotEmpty);

    expect(state().hasError, isTrue);
    expect(state().error, const ConnectionFailure.missingVpnPermission());
    dialogs.open!.complete();
    await _settle();
  });

  test('a status the core sends while the failure dialog is open wins', () async {
    dialogs.open = Completer();
    await notifier().toggleConnection();
    await _until(() => repo.connects == 1);
    repo.connecting!.complete(left(const ConnectionFailure.unexpected('late')));
    await _until(() => dialogs.shown.isNotEmpty);

    // The tunnel came up after all.
    repo.report(const Connected());
    await _settle();
    dialogs.open!.complete();
    await _settle();

    expect(state(), const AsyncData<ConnectionStatus>(Connected()));
  });

  // The real start sends the core restart signal on its way out, success or
  // failure. That marks this notifier out of date until it rebuilds, and in
  // debug builds Riverpod refuses a ref call in between, so the failure
  // handler threw before it could show its dialog.
  test('a failed connect shows its dialog after the core restart signal', () async {
    repo.duringConnect = () => container.read(coreRestartSignalProvider.notifier).restart();
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      await notifier().toggleConnection();
      await _until(() => repo.connects == 1);
      repo.connecting!.complete(left(const ConnectionFailure.missingVpnPermission()));
      await _settle();
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
    expect(dialogs.shown, hasLength(1));
    expect(container.read(Preferences.startedByUser), isFalse);
  });

  test('a tap while connected shows Disconnecting before the core stops', () async {
    repo.report(const Connected());
    await _until(() => state() == const AsyncData<ConnectionStatus>(Connected()));

    final tap = notifier().toggleConnection();
    await _until(() => repo.disconnects == 1);

    expect(state(), const AsyncData<ConnectionStatus>(Disconnecting()));

    repo.disconnecting!.complete(right(unit));
    repo.report(const Disconnected());
    await tap;
    await _until(() => state() == const AsyncData<ConnectionStatus>(Disconnected()));
  });

  // Logout or an app update can stop a connect in its first second, while the
  // last status the core reported is still the Disconnected it started from:
  // the stop is then a repeat, which the status stream drops.
  test('a stop the status stream drops as a repeat does not leave Disconnecting', () async {
    await notifier().toggleConnection();
    await _until(() => repo.connects == 1);
    expect(state(), const AsyncData<ConnectionStatus>(Connecting()));

    final abort = notifier().abortConnection();
    await _until(() => repo.disconnects == 1);
    expect(state(), const AsyncData<ConnectionStatus>(Disconnecting()));
    repo.disconnecting!.complete(right(unit));
    // The core reports a stop, which is the same Disconnected again.
    repo.report(const Disconnected());
    await abort;
    await _settle();

    expect(state(), const AsyncData<ConnectionStatus>(Disconnected()));
  });
}

/// Lets microtasks and zero-length timers run until [done], or fails.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition not reached');
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final _profile = ProfileEntity.remote(
  id: 'profile-1',
  active: true,
  name: 'Test',
  url: 'https://example.invalid/sub',
  lastUpdate: DateTime(2026, 11, 23),
);

class _Profile extends ActiveProfile {
  @override
  Stream<ProfileEntity?> build() => Stream.value(_profile);
}

class _Account extends AccountStateNotifier {
  @override
  AccountState build() => const AccountActive();
}

/// Records the dialogs, and keeps one open until [open] completes.
class _Dialogs extends DialogNotifier {
  final shown = <({String type, String? message})>[];
  Completer<void>? open;

  @override
  void build() {}

  @override
  Future<void> showCustomAlertFromErr(({String type, String? message}) err) async {
    shown.add(err);
    await (open?.future ?? Future<void>.value());
  }
}

/// The status stream replays its last value to a new listener, as the core
/// service's does, so a rebuilt notifier starts from the current status.
class _Repo implements ConnectionRepository {
  final _statuses = BehaviorSubject<ConnectionStatus>.seeded(const Disconnected());
  int connects = 0;
  int disconnects = 0;
  Completer<Either<ConnectionFailure, Unit>>? connecting;
  Completer<Either<ConnectionFailure, Unit>>? disconnecting;

  /// Runs inside connect, before it returns: what the real start does there.
  void Function()? duringConnect;

  void report(ConnectionStatus status) => _statuses.add(status);

  Future<void> close() => _statuses.close();

  @override
  SingboxConfigOption? get configOptionsSnapshot => null;

  @override
  TaskEither<ConnectionFailure, Unit> setup() => TaskEither.right(unit);

  /// Drops repeats, as connectionStatusFrom does.
  @override
  Stream<ConnectionStatus> watchConnectionStatus() => _statuses.stream.distinct();

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) => TaskEither(() {
    connects++;
    duringConnect?.call();
    return (connecting = Completer()).future;
  });

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => TaskEither(() {
    disconnects++;
    return (disconnecting = Completer()).future;
  });

  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      TaskEither.right(unit);
}
