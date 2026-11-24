import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../core/log/safe.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/record_live.dart';
import '../../data/records/record_commands.dart';
import '../../data/repositories/inbox_field_kinds.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../home_shell/home_shell_controller.dart';
import '../home_shell/home_tab.dart';
import '../tickets/ticket_detail_controller.dart';
import 'inbox_approvals_controller.dart';
import 'inbox_filter_controller.dart';
import 'inbox_views_controller.dart';
import 'models/inbox_filter.dart';
import 'models/inbox_page.dart';
import 'models/inbox_query.dart';
import 'models/inbox_row.dart';
import 'models/inbox_saved_view.dart';
import 'models/inbox_sort.dart';
import 'models/inbox_timeline.dart';

/// Whose records the list shows (`scope:["me"]` / `scope:["team"]`).
enum InboxScope {
  me('Me'),
  team('My Team');

  const InboxScope(this.label);

  final String label;
}

/// The Inbox tab: records of the person (Me) or of the person's team, newest
/// first, from `records.query`, with the people on them from `people.cards`.
/// Memory only. The last list stays on screen when a read fails or the
/// connection drops; only an empty screen shows the error or offline state.
class InboxController extends GetxController {
  InboxController({
    required this.inbox,
    required this.tickets,
    required this.store,
    required this.connectivity,
    required this.shell,
    required this.newTicketDetail,
    required this.fieldKinds,
    required this.approvals,
    required this.views,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const title = 'Inbox';
  static const searchHint = 'Search records';
  static const searchNote = 'Searching loaded records';
  static const emptyTitle = 'No records yet.';
  static const noMatchTitle = 'No records match your search.';
  static const noFilterMatchTitle = 'No records match the filter.';
  static const errorText =
      'The records could not be read. Use Refresh to try again.';
  static const pageSize = RecordLimits.queryPageSize;
  static const _moreAt = 600.0;
  static const _staleAfter = Duration(seconds: 30);

  final InboxRepository inbox;
  final TicketRepository tickets;
  final SessionStore store;
  final ConnectivityService connectivity;
  final HomeShellController shell;
  final TicketDetailController Function(int id) newTicketDetail;

  /// The field kinds of the Advanced filter's conditions; read only when the
  /// panel needs them.
  final InboxFieldKinds fieldKinds;

  /// The Approvals pane (its list, filter and answers).
  final InboxApprovals approvals;

  /// The saved views (the list, the open view, what was last saved).
  final InboxViews views;
  final DateTime Function() _now;

  final searchField = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();

  final scope = InboxScope.me.obs;
  final query = ''.obs;
  final isSearchFocused = false.obs;

  /// The filter that was applied (the panel's draft is its own controller).
  /// "Search in" holds only entries the Me / My Team switch cannot show:
  /// one of those is the switch.
  final filter = InboxFilter.none.obs;

  /// What the screen shows as a whole. The list itself is [rows].
  final viewState = AppViewState.loading.obs;

  /// The records read so far for [scope] (the page the repository holds).
  final page = Rxn<InboxPage>();

  /// A read of this scope failed and [page] is what was read before.
  final hasError = false.obs;
  final isRefreshing = false.obs;
  final isLoadingMore = false.obs;
  final counts = Rxn<InboxCounts>();

  /// The Approvals pane is shown in place of the list. Never saved.
  final isApprovalsOpen = false.obs;

  /// "Save your changes?" is waiting for an answer (the view shows it).
  final unsavedPrompt = Rxn<UnsavedPrompt>();

  /// The person answered Save or Discard on the way out: back may leave.
  final isLeaving = false.obs;

  final _workers = <Worker>[];
  final _details = <int, TicketDetailController>{};
  int _ask = 0;
  bool _isEntered = false;
  bool _isStartViewDone = false;
  DateTime? _readAt;

  @override
  void onInit() {
    super.onInit();
    approvals.onInit();
    views.onInit();
    views.kept.value = InboxSetup.keyOf(InboxSetup.plain());
    _workers.addAll([
      ever(query, (t) {
        approvals.query.value = t;
        _update();
      }),
      ever(shell.approvalsRequest, (_) => _takeApprovalsRequest()),
      ever(shell.tab, (t) {
        if (t == HomeTab.inbox) _enter();
      }),
      ever(connectivity.state, (s) {
        if (s == AppConnectivity.online && _isEntered && _needsRead) {
          fireAndLog('inbox_controller', () => load());
        }
      }),
      ever(store.current, (_) => _onSession()),
    ]);
    searchFocus.addListener(() => isSearchFocused.value = searchFocus.hasFocus);
    scroll.addListener(_onScroll);
    if (shell.tab.value == HomeTab.inbox) _enter();
    _takeApprovalsRequest();
  }

  bool get isOnline => connectivity.state.value == AppConnectivity.online;

  /// The person looking, lower case.
  String get me => (store.userId ?? '').toLowerCase();

  bool get _needsRead => page.value == null || hasError.value;

  /// "My Team" is offered only to a person who has reports.
  bool get isTeamShown => (counts.value?.reports ?? 0) > 0;

  /// What the header says about the list: "12 records", "1000+ records".
  String get totalLabel {
    final p = page.value;
    if (p == null) return '';
    final n = p.isCapped ? '${counts.value?.cap ?? 1000}+' : '${p.total}';
    return '$n ${p.total == 1 && !p.isCapped ? 'record' : 'records'}';
  }

  /// The loaded records that match the search.
  List<InboxRow> get rows =>
      sortInboxRows(_matching(page.value?.rows ?? const []), filter.value.sort);

  /// Is Timeline the "Search in" choice (a heading for each day)?
  bool get isTimeline => filter.value.wheres.contains(InboxWhere.timeline);

  /// What the list draws: the cards, and with Timeline a heading before each
  /// day's cards (newest day first, over the loaded rows only).
  List<({String? heading, InboxRow? row})> get listItems {
    final all = rows;
    if (!isTimeline) return [for (final r in all) (heading: null, row: r)];
    return [
      for (final d in InboxTimeline.group(all, _now())) ...[
        (heading: d.heading, row: null),
        for (final r in d.rows) (heading: null, row: r),
      ],
    ];
  }

  /// How many lines of the filter say something (the Filter button's badge).
  int get filterCount => filter.value.filterCount();

  /// The empty text: "No records match the filter." with a filter set.
  String get emptyText =>
      filter.value.isServerFilter ? noFilterMatchTitle : emptyTitle;

  bool get hasMore => page.value?.hasMore ?? false;

  // ---- entering and leaving ----------------------------------------------------

  void _enter() {
    if (!_isEntered) {
      _isEntered = true;
      approvals.start();
      fireAndLog('inbox_controller', () => load());
      fireAndLog('inbox_controller', () => loadViews());
      return;
    }
    final at = _readAt;
    if (at == null || DateTime.now().difference(at) > _staleAfter) {
      fireAndLog('inbox_controller', () => load(isSilent: true));
      fireAndLog('inbox_controller', () => approvals.reload());
    }
  }

  // ---- the Approvals pane -------------------------------------------------------

  /// The Approvals button: the pane in place of the list, and back.
  void toggleApprovals() => isApprovalsOpen.value = !isApprovalsOpen.value;

  void openApprovals() => isApprovalsOpen.value = true;

  void closeApprovals() => isApprovalsOpen.value = false;

  /// A notification, the Work Space icon or a link asked for the pane.
  void _takeApprovalsRequest() {
    if (!shell.approvalsRequest.value) return;
    shell.approvalsRequest.value = false;
    openApprovals();
  }

  void _onSession() {
    _ask++;
    page.value = null;
    counts.value = null;
    hasError.value = false;
    isLoadingMore.value = false;
    _readAt = null;
    _closeDetails();
    isApprovalsOpen.value = false;
    approvals.onSession();
    views.onSession(InboxSetup.keyOf(InboxSetup.plain()));
    _isStartViewDone = false;
    unsavedPrompt.value?.reply(UnsavedChoice.cancel);
    unsavedPrompt.value = null;
    if (_isEntered && shell.tab.value == HomeTab.inbox) {
      fireAndLog('inbox_controller', () => loadViews());
    }
    if (_isEntered && shell.tab.value == HomeTab.inbox) approvals.start();
    scope.value = InboxScope.me;
    filter.value = InboxFilter.none;
    _update();
    if (_isEntered && shell.tab.value == HomeTab.inbox) {
      fireAndLog('inbox_controller', () => load());
    }
  }

  // ---- reads --------------------------------------------------------------------

  /// Reads the first page again (as many records as are shown, up to 200) and
  /// the counts. A failed read keeps the list. With no list yet the screen
  /// shows loading; [isSilent] never does.
  Future<void> load({bool isSilent = false}) async {
    final mine = ++_ask;
    if (_needsTeam) {
      await _ensureTeam();
      if (mine != _ask) return;
    }
    final had = page.value;
    if (had == null && !isSilent) viewState.value = AppViewState.loading;
    isRefreshing.value = true;
    isLoadingMore.value = false;
    final shown = had?.rows.length ?? 0;
    final limit = shown.clamp(pageSize, RecordLimits.queryMaxLimit);
    try {
      final results = await Future.wait([
        inbox.query(_queryFor(scope.value), limit: limit),
        inbox.loadCounts().then<InboxCounts?>(
          (c) => c,
          onError: (Object e) {
            AppLog.w('inbox_controller', 'counts not read: $e');
            return null;
          },
        ),
      ]);
      if (mine != _ask) return;
      final read = results[0] as InboxPage?;
      final c = results[1] as InboxCounts?;
      if (c != null) {
        counts.value = c;
        if (scope.value == InboxScope.team && c.reports <= 0) {
          scope.value = InboxScope.me;
          fireAndLog('inbox_controller', () => load(isSilent: true));
          return;
        }
      }
      if (read == null) return;
      page.value = read;
      hasError.value = false;
      _readAt = DateTime.now();
      _learnPeople(read.rows);
    } on SocketCallError catch (e) {
      if (mine != _ask) return;
      _onFailed(e);
    } on InboxQueryError catch (e) {
      AppLog.w('inbox_controller', 'query refused: ${e.message}');
      if (mine != _ask) return;
      hasError.value = true;
    } finally {
      if (mine == _ask) isRefreshing.value = false;
    }
    if (mine == _ask) {
      _update();
      _checkMore();
    }
  }

  void _onFailed(SocketCallError e) {
    // A dropped connection with a list on screen is the offline bar's news,
    // not an error of the list.
    hasError.value = !(e.isConnectionGap && page.value != null);
    if (page.value == null) {
      viewState.value = e.isConnectionGap || !isOnline
          ? AppViewState.offline
          : AppViewState.error;
    }
    if (page.value != null) _update();
  }

  /// The next page, when the end of the list is near.
  Future<void> loadMore() async {
    final p = page.value;
    if (p == null || !p.hasMore || isLoadingMore.value || isRefreshing.value) {
      return;
    }
    if (!isOnline) return;
    final mine = ++_ask;
    isLoadingMore.value = true;
    try {
      final next = await inbox.query(
        _queryFor(scope.value),
        offset: p.received,
        limit: pageSize,
      );
      if (mine != _ask || next == null) return;
      page.value = next;
      _learnPeople(next.rows);
    } on SocketCallError catch (e) {
      if (mine != _ask) return;
      if (!e.isConnectionGap) hasError.value = true;
    } on InboxQueryError catch (e) {
      AppLog.w('inbox_controller', 'query refused: ${e.message}');
    } finally {
      if (mine == _ask) isLoadingMore.value = false;
    }
    if (mine == _ask) {
      _update();
      _checkMore();
    }
  }

  InboxQuery _queryFor(InboxScope s) =>
      filter.value.toQuery(scope: s.name, team: _team);

  /// The reports' names, for the Requests entry (`records.people`).
  List<String> get _team => inbox.people.last.value?.team ?? const [];

  /// Requests is raised by the person and their team: the names are read
  /// once when the filter needs them. A failed read asks for the person only.
  bool get _needsTeam =>
      filter.value.wheres.contains(InboxWhere.requests) &&
      inbox.people.last.value == null;

  Future<void> _ensureTeam() async {
    try {
      await inbox.loadPeople();
    } on SocketCallError catch (e) {
      AppLog.w('inbox_controller', 'people not read: ${e.code}');
    }
  }

  /// Pull to refresh and the Refresh button. Offline there is nothing to
  /// read: the bar says so and the list stays.
  Future<void> refreshList() async {
    if (isApprovalsOpen.value) return approvals.reload();
    if (!isOnline) {
      if (page.value == null) viewState.value = AppViewState.offline;
      return;
    }
    await load(isSilent: true);
  }

  Future<void> retry() => isApprovalsOpen.value ? approvals.reload() : load();

  void _learnPeople(List<InboxRow> rows) {
    fireAndLog(
      'inbox_controller',
      () => inbox.loadCards([for (final r in rows) r.who]),
    );
  }

  // ---- saved views ---------------------------------------------------------------

  /// What is on screen as a saved view's map: the filter and the switch over
  /// the open view's own keys.
  Map<String, dynamic> get _setupNow =>
      InboxSetup.compose(views.base, filter.value, scope.value.name);

  /// Does the screen differ from the open view as it was opened or last saved?
  bool get isViewChanged => views.kept.value != InboxSetup.keyOf(_setupNow);

  /// Back must ask first: the Inbox is shown and holds an unsaved change.
  bool get isBackBlocked =>
      !isLeaving.value && shell.tab.value == HomeTab.inbox && isViewChanged;

  /// Reads the views. The first time, and while the person has not started,
  /// the Default View (else the one named by `default`) opens.
  Future<void> loadViews() async {
    final isStarted = isViewChanged;
    final isRead = await views.load();
    if (!isRead || _isStartViewDone) return;
    _isStartViewDone = true;
    final first = views.startView;
    if (first != null && !isStarted && !isViewChanged) {
      _showView(first.name, first.setup);
    }
  }

  /// The Views button: the list is read again when online (a save from
  /// another device shows); offline the last known list stays.
  Future<void> refreshViews() async {
    if (!isOnline) return;
    await views.load();
  }

  void _showView(String name, Map<String, dynamic> saved) {
    final r = InboxSetup.restore(
      saved,
      isTeamShown: counts.value == null || isTeamShown,
    );
    scope.value = r.scope == InboxWhere.team ? InboxScope.team : InboxScope.me;
    filter.value = r.filter;
    views.open(
      name,
      saved,
      InboxSetup.keyOf(
        InboxSetup.compose(saved, filter.value, scope.value.name),
      ),
    );
    closeApprovals();
    _restart();
  }

  void _showPlain(String name) {
    scope.value = InboxScope.me;
    filter.value = InboxFilter.none;
    views.open(name, const {}, InboxSetup.keyOf(InboxSetup.plain()));
    closeApprovals();
    _restart();
  }

  void _openNamed(String name) {
    final v = views.saved(name.isEmpty ? InboxViewLimits.defaultName : name);
    if (v != null) {
      _showView(v.name, v.setup);
    } else {
      _showPlain(name);
    }
  }

  /// A view of the sheet: asks about a change first.
  Future<bool> openView(String name) async {
    if (!await confirmLeave(isMoving: true)) return false;
    _openNamed(name);
    return true;
  }

  /// "Save view": what is on screen goes into the open view (on the Default
  /// View it is what the Inbox opens on). '' when it worked, else the text.
  Future<String> saveView() async {
    if (!views.isReady) return InboxViews.stillLoading;
    final setup = _setupNow;
    final problem = await views.persist(
      views.openName,
      setup,
      isDefault: views.current.value.isEmpty,
    );
    if (problem.isNotEmpty) return problem;
    views.open(views.current.value, setup, InboxSetup.keyOf(setup));
    AppNotices.success(
      views.current.value.isEmpty ? 'Default View saved' : 'View updated',
    );
    return '';
  }

  /// "Save as new view": the same setup under a new name.
  Future<String> saveAsNew(String raw) async {
    final name = InboxViewRules.clean(raw);
    final early = _nameProblem(name);
    if (early.isNotEmpty) return early;
    final setup = _setupNow;
    final problem = await views.persist(name, setup, isNew: true);
    if (problem.isNotEmpty) return problem;
    views.open(name, setup, InboxSetup.keyOf(setup));
    AppNotices.success('View "$name" saved');
    return '';
  }

  /// "Create view": a new view that holds the plain list. The caller has
  /// asked about a change already ([confirmLeave]).
  Future<String> createView(String raw) async {
    final name = InboxViewRules.clean(raw);
    final early = _nameProblem(name);
    if (early.isNotEmpty) return early;
    final problem = await views.persist(name, InboxSetup.plain(), isNew: true);
    if (problem.isNotEmpty) return problem;
    _showPlain(name);
    AppNotices.success('View "$name" created');
    return '';
  }

  String _nameProblem(String name) {
    if (!views.isReady) return InboxViews.stillLoading;
    return InboxViewRules.problem(name, views.repo.views, isNew: true);
  }

  /// "Remove view" (the caller has asked): the open named view goes and the
  /// Default View opens.
  Future<String> removeView() async {
    final name = views.current.value;
    if (name.isEmpty) return '';
    final problem = await views.remove(name);
    if (problem.isNotEmpty) return problem;
    AppNotices.success('View "$name" removed');
    _openNamed('');
    return '';
  }

  /// "Set as default" / "Clear default" for the open named view.
  Future<String> toggleDefault() async {
    final name = views.current.value;
    if (name.isEmpty) return '';
    return views.setDefault(views.isOpenDefault ? null : name);
  }

  /// Asks "Save your changes?" when the screen holds a change. True when the
  /// caller may go on: nothing changed, Save worked, or Discard (the saved
  /// setup is back on screen; with [isMoving] the caller shows another view
  /// at once, so the list is not read twice). Cancel, or a failed Save,
  /// stays.
  Future<bool> confirmLeave({bool isMoving = false}) async {
    if (!isViewChanged) return true;
    if (unsavedPrompt.value != null) return false;
    final prompt = UnsavedPrompt();
    unsavedPrompt.value = prompt;
    final choice = await prompt.answer;
    if (unsavedPrompt.value == prompt) unsavedPrompt.value = null;
    switch (choice) {
      case UnsavedChoice.cancel:
        return false;
      case UnsavedChoice.discard:
        _discard(isRestarting: !isMoving);
        return true;
      case UnsavedChoice.save:
        final problem = await saveView();
        if (problem.isNotEmpty) {
          AppNotices.error(problem);
          return false;
        }
        return true;
    }
  }

  void _discard({required bool isRestarting}) {
    final r = InboxSetup.restore(
      views.base,
      isTeamShown: counts.value == null || isTeamShown,
    );
    scope.value = r.scope == InboxWhere.team ? InboxScope.team : InboxScope.me;
    filter.value = r.filter;
    if (isRestarting) _restart();
  }

  // ---- scope and search ---------------------------------------------------------

  void selectScope(InboxScope next) {
    if (next == InboxScope.team && !isTeamShown) return;
    final hasWheres = filter.value.wheres.isNotEmpty;
    if (next == scope.value && !hasWheres) return;
    scope.value = next;
    if (hasWheres) filter.value = filter.value.copyWith(wheres: const []);
    _restart();
  }

  void _restart() {
    _ask++;
    page.value = null;
    hasError.value = false;
    isLoadingMore.value = false;
    if (scroll.hasClients) scroll.jumpTo(0);
    _update();
    fireAndLog('inbox_controller', () => load());
  }

  // ---- the filter ---------------------------------------------------------------

  /// A panel for the filter, to open as a sheet. Close it with `onClose`
  /// when the sheet is gone. Facets are read only while it lives.
  InboxFilterController newFilterPanel() {
    final page = this.page.value;
    return InboxFilterController(
      inbox: inbox,
      initial: filter.value,
      baseWhere: scope.value.name,
      isTeamShown: isTeamShown,
      fieldKinds: fieldKinds,
      forms: {
        for (final e in (page?.forms ?? const <String, InboxForm>{}).entries)
          e.key: e.value.caption,
      },
      onApply: applyFilter,
      onClear: clearFilter,
    )..onInit();
  }

  /// Apply: the list goes back to page one and the filtered `records.query`
  /// is sent. A choice of only Me or only My Team is the switch.
  void applyFilter(InboxFilter next) {
    var f = next;
    if (f.wheres.length == 1 &&
        (f.wheres.first == InboxWhere.me ||
            f.wheres.first == InboxWhere.team)) {
      final want = f.wheres.first == InboxWhere.team && isTeamShown
          ? InboxScope.team
          : InboxScope.me;
      scope.value = want;
      f = f.copyWith(wheres: const []);
    }
    filter.value = f;
    closeApprovals();
    _restart();
  }

  /// Clear: every line back to none, the switch on Me.
  void clearFilter() {
    scope.value = InboxScope.me;
    filter.value = InboxFilter.none;
    closeApprovals();
    _restart();
  }

  void onQueryChanged(String text) => query.value = text.trim();

  void clearSearch() {
    searchField.clear();
    query.value = '';
  }

  /// Search over what is loaded (`filterWork`): subject, form, state, who it
  /// is with, who raised it, the number.
  List<InboxRow> _matching(List<InboxRow> all) {
    final q = query.value.toLowerCase();
    if (q.isEmpty) return all;
    bool has(String s) => s.toLowerCase().contains(q);
    return [
      for (final r in all)
        if (has(r.subject) ||
            has(r.form) ||
            has(r.badge) ||
            has(r.holder) ||
            has(r.raiser) ||
            has(_nameOf(r)) ||
            has('${r.id}'))
          r,
    ];
  }

  String _nameOf(InboxRow r) => inbox.cardOf(r.who)?.name ?? '';

  void _update() {
    if (page.value == null) {
      if (viewState.value != AppViewState.error &&
          viewState.value != AppViewState.offline) {
        viewState.value = AppViewState.loading;
      }
      return;
    }
    final all = page.value!.rows;
    viewState.value = all.isEmpty
        ? AppViewState.empty
        : rows.isEmpty
        ? AppViewState.noResults
        : AppViewState.content;
  }

  // ---- paging -------------------------------------------------------------------

  void _onScroll() {
    if (!scroll.hasClients) return;
    if (scroll.position.extentAfter < _moreAt) {
      fireAndLog('inbox_controller', () => loadMore());
    }
  }

  // A short list may not scroll at all: check again once it is drawn.
  void _checkMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed || !scroll.hasClients) return;
      _onScroll();
    });
  }

  // ---- people -------------------------------------------------------------------

  /// The name under a card's face: "You", the person's name when known, else
  /// the user name.
  String whoLabelOf(InboxRow r) {
    inbox.cardRevision.value;
    return r.whoLabel(me, cardName: inbox.cardOf(r.who)?.name);
  }

  String? pictureOf(InboxRow r) {
    inbox.cardRevision.value;
    final a = inbox.cardOf(r.who)?.avatar ?? '';
    return a.isEmpty ? null : a;
  }

  // ---- a card --------------------------------------------------------------------

  /// What a card was delivered with, so its status shows without a read of
  /// its own.
  RecordSummary summaryOf(InboxRow r) {
    final names = [
      for (final n in r.holder.split(','))
        if (n.replaceFirst('@', '').trim().isNotEmpty)
          n.replaceFirst('@', '').trim(),
    ];
    return RecordSummary(
      status: r.state,
      holder: names.isEmpty ? '' : names.first,
      claimants: names.length > 1 ? names : const [],
      completion: r.pct,
      isFinal: r.isFinal,
      ts: r.ts,
      by: r.raiser,
    );
  }

  void open(InboxRow r) => Get.toNamed<dynamic>(AppRoutes.ticketOf(r.id));

  /// The menu was opened: `record.actions`, read once (cached 60 s).
  void openMenu(InboxRow r) {
    fireAndLog('inbox_controller', () => tickets.ensureMenu(r.id));
  }

  TicketDetailController detailOf(InboxRow r) {
    return _details.putIfAbsent(r.id, () {
      final c = newTicketDetail(r.id);
      c.onInit();
      return c;
    });
  }

  void _closeDetails() {
    for (final c in _details.values) {
      c.onClose();
    }
    _details.clear();
  }

  @override
  void onClose() {
    _ask++;
    for (final w in _workers) {
      w.dispose();
    }
    _closeDetails();
    approvals.onClose();
    views.onClose();
    unsavedPrompt.value?.reply(UnsavedChoice.cancel);
    searchField.dispose();
    searchFocus.dispose();
    scroll.dispose();
    super.onClose();
  }
}
