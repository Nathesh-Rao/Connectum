import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/repositories/smart_view_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/smart_view/engine/sv_engine.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../../data/smart_view/sv_columns.dart';
import '../../data/smart_view/sv_prefs.dart';
import '../../data/smart_view/sv_query.dart';
import '../../data/socket/socket_service.dart';
import '../forms/models/form_launch.dart';
import '../tickets/ticket_detail_controller.dart';
import 'models/smart_view_entry.dart';
import 'widgets/smart_view_table.dart';

/// The Smart view tab: the list of structures (the drawer) and the records of
/// the one that is open, as cards. Rows are read by [SmartViewRepository] into
/// an [SvTable] and live in memory only. The controller lives as long as the
/// home, so the last opened view is still there when the tab is shown again.
class SmartViewController extends GetxController {
  SmartViewController({
    required this.repo,
    required this.tickets,
    required this.submissions,
    required this.newTicketDetail,
    SmartViewPrefs? prefs,
  }) : prefs = prefs ?? SmartViewPrefs(),
       mode = Rx<SvViewMode>((prefs ?? SmartViewPrefs()).mode);

  final SmartViewRepository repo;
  final TicketRepository tickets;
  final SubmissionRepository submissions;
  final TicketDetailController Function(int id) newTicketDetail;
  final SmartViewPrefs prefs;

  /// Cards or Table, the app-wide choice (restored before the first frame).
  final Rx<SvViewMode> mode;

  /// Records whose card shows every field; kept for the session, by id.
  final expanded = <int>{}.obs;

  /// The table's last measurement (widths and row heights).
  final tableCache = SmartViewTableCache();

  final table = Rxn<SvTable>();
  final current = Rxn<SvSource>();
  final isAdding = false.obs;

  /// The structures the person may open, in the picker's order.
  final sources = <SvSource>[].obs;
  final listPhase = SvPhase.loading.obs;
  final isDrawerOpen = false.obs;

  /// True while the tab is the one on screen; the drawer is closed when it is
  /// not, and back only closes the drawer while it is.
  final isActive = false.obs;
  final findField = TextEditingController();
  final find = ''.obs;

  /// What the person asked of the open view (search, filters, sort), kept per
  /// view for the session: leaving the tab or switching views keeps it.
  final query = Rx<SmartViewQuery>(SmartViewQuery.none);
  final isSearchOpen = false.obs;
  final searchField = TextEditingController();
  final _queries = <String, SmartViewQuery>{};
  Timer? _searchTimer;
  Object? _inputKey;
  SvEngineInput? _input;
  Object? _shownKey;
  List<SvRow> _shown = const [];
  DateTime Function() clock = DateTime.now;
  final _details = <int, TicketDetailController>{};
  bool _isListRead = false;

  SvSource? get source => table.value?.source;

  /// The structures matching the Find text (name or caption, any case).
  List<SvSource> get shownSources {
    final q = find.value.trim().toLowerCase();
    if (q.isEmpty) return sources.toList();
    return [
      for (final s in sources)
        if (s.name.toLowerCase().contains(q) ||
            s.caption.toLowerCase().contains(q))
          s,
    ];
  }

  void setMode(SvViewMode value) {
    if (mode.value == value) return;
    mode.value = value;
    unawaited(prefs.setMode(value));
  }

  void toggleExpanded(int id) {
    if (!expanded.remove(id)) expanded.add(id);
  }

  void setActive(bool value) {
    isActive.value = value;
    if (!value) isDrawerOpen.value = false;
  }

  void openDrawer() => isDrawerOpen.value = true;

  void closeDrawer() => isDrawerOpen.value = false;

  void setDrawer(bool value) => isDrawerOpen.value = value;

  /// Every way in. The tab alone: the last opened view, else the list.
  /// `#view`: the list. `#view <name>`: that view, the list closed.
  Future<void> enter(SmartViewEntry entry) async {
    setActive(true);
    switch (entry.kind) {
      case SmartViewEntryKind.drawer:
        openDrawer();
        await loadList();
      case SmartViewEntryKind.named:
        closeDrawer();
        _wanted = entry.name;
        await loadList();
        await _showWanted();
      case SmartViewEntryKind.tab:
        await loadList();
        if (current.value == null && listPhase.value == SvPhase.ready) {
          openDrawer();
        }
    }
  }

  /// Reads the structures once; [isForced] reads them again (Retry).
  Future<void> loadList({bool isForced = false}) async {
    if (_isListRead && !isForced) return;
    listPhase.value = SvPhase.loading;
    try {
      final all = SvSources.sorted(await repo.sources(isForced: isForced));
      sources.assignAll(all);
      listPhase.value = all.isEmpty ? SvPhase.empty : SvPhase.ready;
      _isListRead = true;
    } on SocketCallError catch (e) {
      listPhase.value = e.isConnectionGap ? SvPhase.offline : SvPhase.error;
    }
    if (isForced) await _showWanted();
  }

  /// The name `#view <name>` asked for, kept until the list is read (Retry
  /// after a failed read still opens it).
  String? _wanted;

  Future<void> _showWanted() async {
    final name = _wanted;
    if (name == null || listPhase.value != SvPhase.ready) return;
    _wanted = null;
    final hit = SvSources.find(sources.toList(), name);
    if (hit == null) {
      openDrawer();
    } else {
      await show(hit);
    }
  }

  /// Opens [s] in the body and closes the drawer.
  Future<void> show(SvSource s) async {
    closeDrawer();
    if (current.value?.name == s.name && table.value != null) return;
    _closeTable();
    _restoreQuery(s.name);
    current.value = s;
    final t = repo.open(s);
    table.value = t;
    await repo.load(t);
  }

  void _closeTable() {
    final t = table.value;
    if (t != null) repo.close(t);
    for (final d in _details.values) {
      d.onClose();
    }
    _details.clear();
    table.value = null;
  }

  // ---- search, filter, sort: one query per view, cards and table alike ----

  void _restoreQuery(String name) {
    _searchTimer?.cancel();
    final q = _queries[name] ?? SmartViewQuery.none;
    query.value = q;
    searchField.text = q.search;
    isSearchOpen.value = q.search.isNotEmpty;
  }

  void setQuery(SmartViewQuery q) {
    query.value = q;
    final name = current.value?.name;
    if (name != null) _queries[name] = q;
  }

  /// Typing in the search box: the query follows 250 ms after the last key.
  void onSearchTyped(String text) {
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 250),
      () => setQuery(query.value.copyWith(search: text)),
    );
  }

  void openSearch() => isSearchOpen.value = true;

  /// Closing the box keeps nothing typed: the search is cleared with it.
  void closeSearch() {
    _searchTimer?.cancel();
    searchField.clear();
    isSearchOpen.value = false;
    if (query.value.search.isNotEmpty) {
      setQuery(query.value.copyWith(search: ''));
    }
  }

  void clearSearchText() {
    _searchTimer?.cancel();
    searchField.clear();
    if (query.value.search.isNotEmpty) {
      setQuery(query.value.copyWith(search: ''));
    }
  }

  void setScope(String? key) =>
      setQuery(query.value.copyWith(scope: () => key));

  void setConditions(List<SvCondition> list) =>
      setQuery(query.value.copyWith(conditions: list));

  void removeCondition(SvCondition c) => setConditions([
    for (final x in query.value.conditions)
      if (x != c) x,
  ]);

  void setSort(String key, {required bool isAscending}) => setQuery(
    query.value.copyWith(sortKey: () => key, isAscending: isAscending),
  );

  void flipSort() {
    if (query.value.sortKey == null) return;
    setQuery(query.value.copyWith(isAscending: !query.value.isAscending));
  }

  void clearSort() => setQuery(query.value.copyWith(sortKey: () => null));

  /// A table header tap: none, then ascending, then descending, then none.
  void cycleSort(String key) {
    final q = query.value;
    if (q.sortKey != key) {
      setSort(key, isAscending: true);
    } else if (q.isAscending) {
      setSort(key, isAscending: false);
    } else {
      clearSort();
    }
  }

  /// Search text and filters off; the sort stays ("Clear filters").
  void clearFilters() {
    _searchTimer?.cancel();
    searchField.clear();
    setQuery(query.value.copyWith(search: '', conditions: const []));
  }

  /// Everything off: search, scope, filters and sort ("Clear").
  void clearQuery() {
    _searchTimer?.cancel();
    searchField.clear();
    setQuery(SmartViewQuery.none);
  }

  /// The open view's columns (no rows read): the fields a search can be
  /// limited to, filtered on or sorted by. Hidden fields are not among them.
  SmartViewColumns? get columns {
    final s = table.value?.source;
    if (s == null) return null;
    if (_columns?.source != s) _columns = SmartViewColumns.of(s);
    return _columns;
  }

  SmartViewColumns? _columns;

  /// The engine's input for the loaded rows, built once per data version.
  /// Reads the table reactively, so an Obx that calls it follows new pages.
  SvEngineInput? get engineInput {
    final t = table.value;
    if (t == null) return null;
    final rows = t.rows.toList();
    final key = Object.hash(
      t.source.name,
      rows.length,
      Object.hashAll(rows.map(identityHashCode)),
    );
    if (_input == null || _inputKey != key) {
      _inputKey = key;
      _input = SvEngineInput.of(SmartViewColumns.of(t.source), rows);
    }
    return _input;
  }

  /// The rows both Cards and Table draw: the loaded rows through the query.
  List<SvRow> get shownRows {
    final t = table.value;
    if (t == null) return const [];
    final q = query.value;
    if (!q.isFiltering && !q.isSorting) {
      _shownKey = null;
      return t.rows.toList();
    }
    final input = engineInput!;
    final key = Object.hash(_inputKey, q);
    if (_shownKey != key) {
      _shown = input.apply(q, now: clock());
      _shownKey = key;
    }
    return _shown;
  }

  /// More pages are still to come (or failed): a result is partial.
  bool get hasMorePages {
    final t = table.value;
    if (t == null) return false;
    return t.isPaging.value ||
        t.hasPartialError.value ||
        (t.isCapped.value && t.total.value > t.rows.length);
  }

  /// "Load more": a read that is under way continues by itself, so this only
  /// starts one (the existing quiet re-read) when none is running.
  Future<void> loadMore() async {
    final t = table.value;
    if (t == null || t.isPaging.value) return;
    await repo.refresh(t);
  }

  /// What the screen shows: the list is read first, then the open view's rows.
  AppViewState get viewState {
    final t = table.value;
    if (t == null) {
      return switch (listPhase.value) {
        SvPhase.loading => AppViewState.loading,
        SvPhase.error => AppViewState.error,
        SvPhase.offline => AppViewState.offline,
        SvPhase.empty => AppViewState.empty,
        _ => AppViewState.empty,
      };
    }
    return switch (t.phase.value) {
      SvPhase.loading => AppViewState.loading,
      SvPhase.ready => AppViewState.content,
      SvPhase.empty => AppViewState.empty,
      SvPhase.error => AppViewState.error,
      SvPhase.offline => AppViewState.offline,
      SvPhase.noAccess => AppViewState.locked,
    };
  }

  /// True when nothing is open yet and the list has views to choose from.
  bool get isChoosing =>
      table.value == null && listPhase.value == SvPhase.ready;

  String get title => current.value?.caption ?? 'Smart view';

  /// Pull to refresh and Retry: the rows stay until the new ones land.
  Future<void> reload() async {
    final t = table.value;
    if (t == null) {
      await loadList(isForced: true);
    } else {
      await repo.refresh(t);
    }
  }

  /// A record opens the way the web opens it: a record with a status, or one
  /// sent to me, in the record screen; a plain submission in its own view.
  void open(SvRow row) {
    final s = source;
    if (s != null && (s.hasStatus || row.isReceived)) {
      Get.toNamed(AppRoutes.ticketOf(row.id));
      return;
    }
    Get.toNamed(AppRoutes.submissionDetailOf('${row.id}'));
  }

  /// The structure's add form (`tstruct.user.open`, as `#tstruct-add`), then
  /// back here: the saved record shows when the server has it.
  Future<void> add() async {
    final s = source;
    final t = table.value;
    if (s == null || t == null || isAdding.value) return;
    isAdding.value = true;
    try {
      final open = await submissions.openStructure(s.name);
      if (!open.isOpen) {
        AppNotices.warning(
          open.isOffline
              ? 'Needs a connection'
              : open.code == 'not_found' && open.message.isNotEmpty
              ? open.message
              : "Couldn't open that structure. Try again.",
        );
        return;
      }
      final result = await Get.toNamed(
        AppRoutes.form,
        arguments: FormLaunch(
          name: open.name,
          scope: open.scope,
          caption: open.caption,
        ),
      );
      if (result == true) unawaited(repo.refreshNewest(t));
    } finally {
      isAdding.value = false;
    }
  }

  // ---- the card's bar and menu: the queue's, nothing new per card ---------

  /// The menu is opened: its actions are read once (cached 60 s).
  void openRecordMenu(int id) => unawaited(tickets.ensureMenu(id));

  TicketDetailController detailOf(int id) => _details.putIfAbsent(id, () {
    final c = newTicketDetail(id);
    c.onInit();
    return c;
  });

  @override
  void onClose() {
    _searchTimer?.cancel();
    _closeTable();
    searchField.dispose();
    findField.dispose();
    super.onClose();
  }
}
