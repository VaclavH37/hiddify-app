import 'package:hiddify/features/profile/model/hub_reachability.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// The fast path's two views of the core's outbound groups: what is in use,
/// and every location.
///
/// Read from the full outbounds stream, where a group lists all its members
/// (the main stream lists only each group's chosen one, which is how a single
/// failing location came to read as a dead hub, 2026-10-18).
///
/// - selected: each group's chosen entry, by the group's own `selected` tag. The
///   per-item `isSelected` flag is not used: the core builds one record per
///   outbound and shares it between groups, so a later group overwrites what an
///   earlier one set. A chosen entry that is itself a group (the selector's
///   "lowest") carries its own chosen location's result.
/// - all: every location once, by tag. Groups are left out, since they only
///   repeat a member's result, and so are hidden internal outbounds.
UrlTestSnapshot urlTestSnapshotOf(List<OutboundGroup> groups) {
  ExitObservation observed(OutboundInfo item) =>
      (delay: item.urlTestDelay, testedAt: item.hasUrlTestTime() ? item.urlTestTime.toDateTime() : null);

  final selected = <ExitObservation>[];
  final locations = <String, ExitObservation>{};
  for (final group in groups) {
    for (final item in group.items) {
      if (item.tag.contains('§hide§')) continue;
      if (item.tag == group.selected) selected.add(observed(item));
      if (!item.isGroup) locations[item.tag] = observed(item);
    }
  }
  return (selected: selected, all: locations.values.toList());
}
