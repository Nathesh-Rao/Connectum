import 'dart:async';

import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import 'models/approval_chips.dart';
import 'approval_filter_controller.dart';
import 'models/approval_entries.dart';
import 'models/approval_panel.dart';
import 'models/approval_pane.dart';
import 'models/approval_quick_filter.dart';
import 'models/inbox_approval_rows.dart';
import 'models/inbox_filter.dart';
import 'models/approval_reducer.dart';
import 'models/approval_rules.dart';

/// The Approvals pane of the Inbox: the requests of [ApprovalRepository]
/// (every status, newest first), the dropdown, the search text of the Inbox,
/// and the answers. Memory only; nothing is saved. Owned by
/// [InboxController], which opens and closes the pane.
class InboxApprovals extends GetxController {
  InboxApprovals({
    required this.approvals,
    required this.inbox,
    required this.connectivity,
    this.me = '',
    DateTime Function()? now,
    this.afterAnswer = const Duration(milliseconds: 260),
  }) : _now = now ?? DateTime.now;

  static const noteMax = ApprovalRules.maxText;

  final ApprovalRepository approvals;
  final InboxRepository inbox;
  final ConnectivityService connectivity;

  /// The signed-in username, lower case, for From me / To me.
  final String me;
  final DateTime Function() _now;

  /// How long an answered card slides out before the list is read again.
  final Duration afterAnswer;

  /// The primary chip (All, Pending, Approved, Requests, Rejected) and the
  /// side of the Me / My Team toggle. Memory only: never saved in a view.
  final primary = ApprovalPrimary.all.obs;
  final side = ApprovalSide.me.obs;

  /// The secondary chips that are on (memory only, never saved in a view).
  final chips = const ApprovalChipFilter().obs;

  /// The filter panel as applied: the entries ticked and the other lines.
  /// Memory only: kept while the person switches tabs and chips, never saved
  /// in a view.
  final panel = ApprovalPanel.none.obs;

  /// Cards whose body is open ("Show more"), by key.
  final expanded = <String>{}.obs;

  /// The Inbox search text of the Records tab (it also filters the approvals
  /// drawn under the records).
  final query = ''.obs;

  /// The search text of the Approvals tab.
  final paneQuery = ''.obs;

  /// Answered cards that are still sliding out of the list.
  final leaving = <int>{}.obs;

  /// Requests with an answer in flight: no second one starts.
  final busy = <int>{}.obs;

  final _timers = <Timer>[];
  Worker? _learnWorker;
  Worker? _teamWorker;
  Worker? _reportsWorker;

  @override
  void onInit() {
    super.onInit();
    _learnWorker = ever(approvals.all, (_) => _learnPeople());
    _teamWorker = ever(approvals.team, (_) => _learnPeople());
    _reportsWorker = ever(inbox.counts.last, (_) => _syncReports());
    _syncReports();
  }

  /// The person has direct reports: the toggle shows and `req.team` is read.
  bool get hasTeam => (inbox.counts.last.value?.reports ?? 0) > 0;

  void _syncReports() {
    final had = approvals.hasReports.value;
    approvals.hasReports.value = hasTeam;
    if (had != hasTeam && approvals.hasRead.value) {
      fireAndLog('inbox_approvals', approvals.refreshTeam);
    }
    if (!hasTeam) side.value = ApprovalSide.me;
  }

  @override
  void onClose() {
    _learnWorker?.dispose();
    _teamWorker?.dispose();
    _reportsWorker?.dispose();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    super.onClose();
  }

  bool get isOnline => connectivity.state.value == AppConnectivity.online;

  /// The Approvals button's number.
  int get count => approvals.count.value;

  /// The read failed and the list shown is the one read before.
  bool get hasError => approvals.hasError.value && approvals.hasRead.value;

  ApprovalChipContext get _chipContext =>
      ApprovalChipContext(me: me, now: _now());

  /// The side the list is on: My Team only with direct reports.
  ApprovalSide get effectiveSide => hasTeam ? side.value : ApprovalSide.me;

  /// The requests of the person and, for a manager, of their team (a request
  /// that is in both is the person's own: it has the buttons).
  List<Approval> get pool {
    final own = approvals.all;
    if (approvals.team.isEmpty) return own.toList();
    final have = {for (final a in own) a.id};
    return [
      ...own,
      for (final a in approvals.team)
        if (!have.contains(a.id)) a,
    ];
  }

  /// The person and their reports, for the entries.
  ApprovalWho get whoOf => _who;

  ApprovalWho get _who => ApprovalWho.of(me, [
    for (final a in approvals.team) a.fromUser,
    ...(inbox.people.last.value?.team ?? const <String>[]),
  ]);

  /// Listed rows that match the search, in every state.
  List<Approval> get _searched =>
      ApprovalPane.rows(pool, query: paneQuery.value, nameOf: _nameOf);

  /// The requests that pass the search, the secondary chips and the panel's
  /// lines (before the entries), in the order Sort says.
  List<Approval> get _base {
    final kept = [
      for (final a in ApprovalReducer.sorted(_searched))
        if (chips.value.matches(a, _chipContext)) a,
    ];
    return ApprovalPanelRules.narrow(kept, panel.value, pool: pool);
  }

  /// The entries the list is cut by: the ones ticked, else the toggle's side
  /// of the chip.
  List<ApprovalEntry> get effectiveEntries => ApprovalPanelRules.effective(
    primary.value,
    side.value,
    panel.value.entries,
    hasTeam: hasTeam,
  );

  /// What the toggle shows: the side the ticked entries are, none when they
  /// are mixed, else the side it is on.
  ApprovalSide? get shownSide => panel.value.entries.isEmpty
      ? effectiveSide
      : ApprovalPanelRules.sideOf(effectiveEntries);

  /// The filter button's badge: only what the person changed.
  int get panelCount => panel.value.count;

  /// The numbers on the primary chips: each counts its entries over the rows
  /// the search, the secondary chips and the panel keep. The chip that is on
  /// counts the entries ticked.
  Map<ApprovalPrimary, int> get primaryCounts {
    primary.value;
    side.value;
    chips.value;
    panel.value;
    final base = _base;
    return {
      for (final c in ApprovalPrimary.values)
        c: base
            .where(
              (a) => ApprovalPanelRules.inEntries(
                a,
                ApprovalPanelRules.effective(
                  c,
                  side.value,
                  c == primary.value ? panel.value.entries : const [],
                  hasTeam: hasTeam,
                ),
                _who,
              ),
            )
            .length,
    };
  }

  /// The secondary chips to draw, group by group, with their live counts,
  /// over the rows of the primary chip and side.
  List<List<ApprovalChipView>> get chipViews {
    chips.value;
    panel.value;
    final entries = effectiveEntries;
    final inChip = [
      for (final a in _base)
        if (ApprovalPanelRules.inEntries(a, entries, _who)) a,
    ];
    return ApprovalChips.viewsOf(inChip, chips.value, _chipContext);
  }

  bool get hasChipsOn => !chips.value.isEmpty;

  bool _kept(Approval a) =>
      ApprovalPanelRules.inEntries(a, effectiveEntries, _who) &&
      chips.value.matches(a, _chipContext) &&
      ApprovalPane.matches(a, paneQuery.value, personName: _nameOf(a)) &&
      ApprovalPanelRules.narrow([a], panel.value, pool: pool).isNotEmpty;

  /// The cards: the rows the entries, chips, search and panel keep, in the
  /// order Sort says, and the ones just answered that are still sliding out.
  List<Approval> get rows {
    inbox.cardRevision.value;
    primary.value;
    side.value;
    panel.value;
    chips.value;
    final entries = effectiveEntries;
    final candidates = [
      for (final a in ApprovalReducer.sorted(pool))
        if (leaving.contains(a.id) ||
            (ApprovalPanelRules.inEntries(a, entries, _who) &&
                chips.value.matches(a, _chipContext) &&
                ApprovalPane.matches(
                  a,
                  paneQuery.value,
                  personName: _nameOf(a),
                )))
          a,
    ];
    return ApprovalPanelRules.narrow(candidates, panel.value, pool: pool);
  }

  /// This card has been answered and no longer belongs to the list.
  /// Some request of the person's own is listed (a tour's sample never is).
  bool get hasListed => ApprovalPane.listed(pool).isNotEmpty;

  bool isLeaving(Approval a) => leaving.contains(a.id) && !_kept(a);

  AppViewState get viewState {
    if (!approvals.hasRead.value) {
      if (!approvals.hasError.value) return AppViewState.loading;
      return approvals.isOfflineError.value || !isOnline
          ? AppViewState.offline
          : AppViewState.error;
    }
    if (ApprovalPane.listed(pool).isEmpty) return AppViewState.empty;
    return rows.isEmpty ? AppViewState.noResults : AppViewState.content;
  }

  bool isEscalated(Approval a) => ApprovalPane.isEscalated(a, _now());

  // ---- in the Inbox list -----------------------------------------------------

  /// The approvals the Inbox list draws for [f]: under the records, or alone
  /// (`InboxApprovalRows`). Answered cards that are still sliding out stay
  /// where they were until the list is read again.
  List<Approval> cardsFor(InboxFilter f) {
    inbox.cardRevision.value;
    final plan = InboxApprovalRows(f);
    final base = plan.cards(
      approvals.all,
      query: query.value,
      nameOf: _nameOf,
      now: _now(),
    );
    if (leaving.isEmpty) return base;
    final ids = {for (final a in base) a.id};
    final out = [...base];
    for (final a in ApprovalReducer.sorted(approvals.all)) {
      if (!leaving.contains(a.id) || ids.contains(a.id)) continue;
      final at = out.indexWhere((x) => x.createdTs < a.createdTs);
      out.insert(at < 0 ? out.length : at, a);
    }
    return out;
  }

  /// This card was answered and no longer belongs to the Inbox list for [f].
  bool isLeavingFor(InboxFilter f, Approval a) =>
      leaving.contains(a.id) &&
      !InboxApprovalRows(f)
          .cards(
            approvals.all,
            query: query.value,
            nameOf: _nameOf,
            now: _now(),
          )
          .any((x) => x.id == a.id);

  /// The shared list was read at least once.
  bool get isRead => approvals.hasRead.value;

  /// The first read failed (nothing to show yet).
  bool get hasFailedRead =>
      !approvals.hasRead.value && approvals.hasError.value;

  // ---- reading ---------------------------------------------------------------

  /// The Inbox was shown: read once, and keep the list fresh from now on.
  void start() => fireAndLog('inbox_approvals', approvals.start);

  /// Refresh, Retry and pull to refresh. Offline with nothing read yet: the
  /// state says so and nothing is sent.
  Future<void> reload() async {
    if (!isOnline && !approvals.hasRead.value) return;
    await approvals.refresh();
  }

  /// The session changed: nothing of the last one stays.
  void onSession() {
    approvals.reset();
    clearFilters();
    expanded.clear();
    leaving.clear();
    busy.clear();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void toggleChip(ApprovalChipGroup g, String key) =>
      chips.value = chips.value.toggle(g, key);

  void clearChips() => chips.value = chips.value.clear();

  /// A primary chip is pressed; the secondary chips and the panel's lines
  /// stay, what was ticked for the old chip is dropped. It sets no filter.
  void pickPrimary(ApprovalPrimary p) {
    primary.value = p;
    panel.value = panel.value.copyWith(entries: const []);
  }

  /// The toggle is pressed: that side (My Team only with direct reports).
  void pickSide(ApprovalSide s) {
    if (s == ApprovalSide.team && !hasTeam) return;
    side.value = s;
    panel.value = panel.value.copyWith(entries: const []);
  }

  // ---- the filter panel ------------------------------------------------------

  /// A panel to open as a popup; its draft starts from the lines as applied.
  ApprovalFilterController newPanel() =>
      ApprovalFilterController(approvals: this, initial: panel.value);

  /// Apply: the entries ticked (only ones the chip offers; none is the
  /// toggle's side) and the other lines. If the entries are all of one side
  /// the toggle follows them.
  void applyPanel(ApprovalPanel draft) {
    final known = ApprovalPanelRules.offered(primary.value, hasTeam);
    final entries = [
      for (final e in known)
        if (draft.entries.contains(e)) e,
    ];
    final next = ApprovalPanelRules.sideOf(entries);
    if (next != null) side.value = next;
    panel.value = draft.copyWith(entries: entries);
  }

  // ---- the filters popup -----------------------------------------------------

  /// A draft for the filters popup, from what is applied now.
  ApprovalQuickDraft newQuickDraft() => ApprovalQuickDraft(
    hasTeam: hasTeam,
    primary: primary.value,
    side: shownSide ?? effectiveSide,
    entries: panel.value.entries,
  );

  /// Apply the popup: the status, the side and the entries ticked; the other
  /// lines of the panel stay.
  void applyQuick(
    ApprovalPrimary p,
    ApprovalSide s,
    List<ApprovalEntry> entries,
  ) {
    primary.value = p;
    side.value = s == ApprovalSide.team && !hasTeam ? ApprovalSide.me : s;
    applyPanel(panel.value.copyWith(entries: entries));
  }

  /// Clear from the popup: All, the person's own side, no entry; the other
  /// lines of the panel stay.
  void clearQuick() =>
      applyQuick(ApprovalPrimary.all, ApprovalSide.me, const []);

  /// The × of a selected chip.
  void removeSelected(ApprovalSelected s) {
    final entries = panel.value.entries;
    switch (s.kind) {
      case ApprovalSelectedKind.status:
        applyQuick(ApprovalPrimary.all, side.value, entries);
      case ApprovalSelectedKind.scope:
        applyQuick(primary.value, ApprovalSide.me, entries);
      case ApprovalSelectedKind.entry:
        applyQuick(primary.value, side.value, [
          for (final e in entries)
            if (e != s.entry) e,
        ]);
    }
  }

  /// The numbers on the status options of the popup for [s], over the rows the
  /// search, the chips and the panel's lines keep.
  Map<ApprovalPrimary, int> statusCountsFor(ApprovalSide s) {
    chips.value;
    panel.value;
    final base = _base;
    return {
      for (final c in ApprovalPrimary.values)
        c: base
            .where(
              (a) => ApprovalPanelRules.inEntries(
                a,
                ApprovalPanelRules.effective(c, s, const [], hasTeam: hasTeam),
                _who,
              ),
            )
            .length,
    };
  }

  /// The number behind each entry, over the same rows.
  Map<ApprovalEntry, int> get entryCounts {
    chips.value;
    panel.value;
    final base = _base;
    return {
      for (final e in ApprovalEntry.values)
        e: base.where((a) => ApprovalEntries.inEntry(a, e, _who)).length,
    };
  }

  /// Clear: nothing ticked and the other lines empty (the toggle stays).
  void clearPanel() => panel.value = ApprovalPanel.none;

  /// How one person is shown: the name people.cards gave, else the user name;
  /// "Me" for the person.
  String nameOfUser(String user) {
    inbox.cardRevision.value;
    if (me.isNotEmpty && user.toLowerCase() == me.toLowerCase()) return 'Me';
    final n = inbox.cardOf(user)?.name ?? '';
    return n.isEmpty ? user : n;
  }

  String? pictureOfUser(String user) {
    inbox.cardRevision.value;
    final p = inbox.cardOf(user)?.avatar ?? '';
    return p.isEmpty ? null : p;
  }

  /// All, on the person's own side, no secondary chip on: how the tab opens
  /// from a "Review approval" notification and after a new session.
  void clearFilters() {
    primary.value = ApprovalPrimary.all;
    side.value = ApprovalSide.me;
    chips.value = const ApprovalChipFilter();
    panel.value = ApprovalPanel.none;
  }

  bool isExpanded(String key) => expanded.contains(key);

  void toggleExpanded(String key) {
    if (!expanded.remove(key)) expanded.add(key);
  }

  String _nameOf(Approval a) => inbox.cardOf(a.from)?.name ?? '';

  /// The name under a card's face: the person's name when known, else the
  /// name the request carries.
  String whoLabelOf(Approval a) {
    inbox.cardRevision.value;
    final n = _nameOf(a);
    return n.isNotEmpty ? n : a.fromLabel;
  }

  String? pictureOf(Approval a) {
    inbox.cardRevision.value;
    final p = inbox.cardOf(a.from)?.avatar ?? '';
    return p.isEmpty ? null : p;
  }

  void _learnPeople() {
    final names = {
      for (final a in [...approvals.all, ...approvals.team]) ...[
        if (a.from.isNotEmpty) a.from,
        ...a.approvers.where((u) => u.isNotEmpty),
      ],
    };
    if (names.isEmpty) return;
    fireAndLog('inbox_approvals', () => inbox.loadCards(names));
  }

  // ---- answering -------------------------------------------------------------

  /// Sends one answer. True when the server took it: the card slides out and
  /// the list is read again after [afterAnswer], so the server has the last
  /// word. A refusal shows the server's own words.
  Future<bool> respond(
    Approval a,
    ApprovalAction action, {
    String reason = '',
    String comment = '',
    bool allowResubmit = false,
  }) async {
    if (busy.contains(a.id)) return false;
    final answer = ApprovalRules.answerFor(
      a,
      action,
      reason: reason,
      comment: comment,
      allowResubmit: allowResubmit,
    );
    if (answer == null) return false;
    busy.add(a.id);
    try {
      await approvals.respond(
        a.id,
        action.wire,
        reason: answer.reason,
        comment: answer.comment,
        allowResubmit: answer.allowResubmit,
      );
      leaving.add(a.id);
      _timers.add(
        Timer(afterAnswer, () {
          leaving.remove(a.id);
          fireAndLog('inbox_approvals', approvals.refresh);
        }),
      );
      return true;
    } on SocketCallError catch (e) {
      final problem = CallProblem.of(e, isWrite: true);
      AppNotices.error(problem.text);
      if (problem.shouldRefresh) {
        fireAndLog('inbox_approvals', approvals.refresh);
      }
      return false;
    } finally {
      busy.remove(a.id);
    }
  }
}
