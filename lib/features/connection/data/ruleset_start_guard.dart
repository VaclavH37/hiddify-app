import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/rulesets/ruleset_store.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:loggy/loggy.dart';
import 'package:meta/meta.dart';

/// The core's own message when [failure] is the core refusing to start, or
/// null for anything else: a missing permission, an unreadable config, a core
/// process that is not running.
///
/// Recognised by the shapes the start paths give it. A start reports
/// `getCoreAlert()`'s `"<alert> - <message>"` (`startService`, `createService`,
/// `startFailed`); a restart reports `"<MessageType> <message>"`
/// (`START_SERVICE`, `CREATE_SERVICE`).
@visibleForTesting
String? coreStartFailureMessage(ConnectionFailure failure) {
  if (failure case UnexpectedConnectionFailure(:final error) when error is String) {
    const markers = ['startService - ', 'createService - ', 'startFailed - ', 'START_SERVICE ', 'CREATE_SERVICE '];
    if (markers.any(error.startsWith)) return error;
  }
  return null;
}

/// Whether a core message names a rule-set. sing-box reports a file it cannot
/// load as `initialize router: parse rule-set[i]: ...`.
@visibleForTesting
bool namesRuleSet(String message) {
  final lower = message.toLowerCase();
  return lower.contains('rule-set') || lower.contains('rule_set') || lower.contains('ruleset');
}

enum RulesetStartAction { none, revert, revertAndRetry }

/// What a failed core start means for the rule-sets on disk.
///
/// - The core named a rule-set and a downloaded set is installed: put the
///   bundle back, reject that version, and start once more.
/// - Any other core-start failure while a download is still pending (installed
///   but not yet through a successful start): put the bundle back and reject
///   it, without a retry. The bundle is known to load, so this costs at most
///   one version's worth of updates if the download was not the cause.
/// - Otherwise nothing: the bundle is installed, or the failure is not the
///   core refusing to start.
@visibleForTesting
RulesetStartAction rulesetStartAction({
  required String? coreMessage,
  required bool pending,
  required bool downloadInstalled,
}) {
  if (coreMessage == null || !downloadInstalled) return RulesetStartAction.none;
  if (namesRuleSet(coreMessage)) return RulesetStartAction.revertAndRetry;
  return pending ? RulesetStartAction.revert : RulesetStartAction.none;
}

/// Keeps a downloaded rule-set from stopping the VPN.
///
/// A rule-set the core cannot load is fatal to the next start. The updater
/// and the mirror both check every file, so this is the last line: it wraps
/// each core start and restart. A start that succeeds confirms a pending
/// download. A start that fails because of one puts the bundle back, rejects
/// that version so it is never downloaded again, and starts once more, so the
/// user sees one connect, not an error.
///
/// Never makes a start worse: if anything here fails, the original result is
/// returned as it was.
class RulesetStartGuard {
  RulesetStartGuard(this._store);

  final RulesetStore _store;

  static final _log = Loggy('ruleset_start_guard');

  Future<Either<ConnectionFailure, Unit>> run(Future<Either<ConnectionFailure, Unit>> Function() start) async {
    final first = await start();
    try {
      switch (first) {
        case Right():
          await _store.confirmPending();
          return first;
        case Left(value: final failure):
          return await _recover(failure, first, start);
      }
    } catch (e, st) {
      _log.warning('rule-set start guard failed; returning the start result unchanged', e, st);
      return first;
    }
  }

  Future<Either<ConnectionFailure, Unit>> _recover(
    ConnectionFailure failure,
    Either<ConnectionFailure, Unit> first,
    Future<Either<ConnectionFailure, Unit>> Function() start,
  ) async {
    final message = coreStartFailureMessage(failure);
    if (message == null) return first;
    final download = await _store.installedDownloadVersion();
    final pending = (await _store.readState()).pending;
    final action = rulesetStartAction(
      coreMessage: message,
      pending: pending != null && pending == download,
      downloadInstalled: download != null,
    );
    if (action == RulesetStartAction.none) return first;

    _log.warning(
      'core refused to start with downloaded rule-sets $download'
      '${namesRuleSet(message) ? ' (it named a rule-set)' : ''}; reverting to the bundle',
    );
    try {
      await _store.revertToBundled(reject: download);
    } catch (e) {
      // The rejection is already on file, so the next launch restores the
      // bundle before the core starts. Retrying now would meet the same files.
      _log.warning('could not put the bundle back now; it will be at the next launch: $e');
      return first;
    }
    if (action != RulesetStartAction.revertAndRetry) return first;

    _log.info('starting again on the bundled rule-sets');
    final second = await start();
    if (second.isRight()) await _store.confirmPending();
    return second;
  }
}
