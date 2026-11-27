import 'package:get/get.dart';

import 'approval_entries.dart';
import 'approval_panel.dart';

/// What a selected chip of the Approvals filter bar stands for.
enum ApprovalSelectedKind { status, scope, entry }

/// One selected filter, drawn as a removable chip.
class ApprovalSelected {
  const ApprovalSelected({required this.kind, required this.label, this.entry});

  final ApprovalSelectedKind kind;
  final String label;
  final ApprovalEntry? entry;

  String get id => entry?.name ?? kind.name;
}

/// The filters the person picked for the Approvals tab: a status (primary
/// chip), the side, and the entries. Pure.
class ApprovalQuick {
  ApprovalQuick._();

  /// The selected filters in the order the bar draws them. The side shows
  /// only when no entry is ticked (ticked entries already say which side).
  static List<ApprovalSelected> selectedOf(
    ApprovalPrimary primary,
    ApprovalSide side,
    List<ApprovalEntry> entries,
  ) => [
    if (primary != ApprovalPrimary.all)
      ApprovalSelected(kind: ApprovalSelectedKind.status, label: primary.label),
    if (side == ApprovalSide.team && entries.isEmpty)
      const ApprovalSelected(
        kind: ApprovalSelectedKind.scope,
        label: 'My Team',
      ),
    for (final e in entries)
      ApprovalSelected(
        kind: ApprovalSelectedKind.entry,
        label: e.label,
        entry: e,
      ),
  ];
}

/// The draft of the filters popup: nothing applies until Apply.
class ApprovalQuickDraft {
  ApprovalQuickDraft({
    required this.hasTeam,
    ApprovalPrimary primary = ApprovalPrimary.all,
    ApprovalSide side = ApprovalSide.me,
    List<ApprovalEntry> entries = const [],
  }) : primary = primary.obs,
       side = side.obs,
       entries = entries.toList().obs;

  final bool hasTeam;
  final Rx<ApprovalPrimary> primary;
  final Rx<ApprovalSide> side;
  final RxList<ApprovalEntry> entries;

  /// The entries the status offers.
  List<ApprovalEntry> get offered =>
      ApprovalPanelRules.offered(primary.value, hasTeam);

  /// How many filters the draft holds.
  int get count =>
      ApprovalQuick.selectedOf(primary.value, side.value, entries).length;

  void pickPrimary(ApprovalPrimary p) {
    primary.value = p;
    final known = offered;
    entries.removeWhere((e) => !known.contains(e));
    _followEntries();
  }

  void pickSide(ApprovalSide s) {
    if (s == ApprovalSide.team && !hasTeam) return;
    side.value = s;
    entries.clear();
  }

  void toggleEntry(ApprovalEntry e) {
    if (!entries.remove(e)) entries.add(e);
    _followEntries();
  }

  void clear() {
    primary.value = ApprovalPrimary.all;
    side.value = ApprovalSide.me;
    entries.clear();
  }

  void _followEntries() {
    final s = ApprovalPanelRules.sideOf(entries);
    if (s != null) side.value = s;
  }
}
