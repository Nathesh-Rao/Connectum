import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/crash/crash_breadcrumbs.dart';

import '../../core/debug/records_log.dart';
import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/tour/tour.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import 'package:connectum/data/socket/socket.dart';
import '../../core/routes/app_routes.dart';
import '../../data/smart_view/engine/sv_engine.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/smart_view/models/sv_source.dart';
import '../../data/smart_view/sv_columns.dart';
import '../../data/smart_view/sv_file.dart';
import '../../data/smart_view/sv_prefs.dart';
import '../../data/smart_view/sv_saved_view.dart';
import '../../data/smart_view/sv_query.dart';
import '../../data/smart_view/sv_team.dart';
import '../forms/models/form_launch.dart';
import '../tickets/ticket_detail_controller.dart';
import 'models/smart_view_entry.dart';
import 'widgets/sv_team_lines.dart';
import 'sv_file_preview_controller.dart';
import 'widgets/smart_view_table.dart';
import 'smart_view_tour.dart';
import 'smart_view_tour_demo.dart';

enum SvViewsPhase { loading, ready, error }

/// The rows of a grouped list in group order, and the lines to draw: group
/// headers and rows ([SvFlat.row] holds an index into [rows]).
class SvGrouped {
  const SvGrouped(this.rows, this.flat, this.sumLabel);

  final List<SvRow> rows;
  final List<SvFlat> flat;

  /// The caption of the column the headers total (null: no number column).
  final String? sumLabel;
}

/// The Smart view tab: the list of structures (the drawer) and the records of
/// the one that is open, as cards or a table. Rows are read by
/// [SmartViewRepository] into an [SvTable] and live in memory only.
class SmartViewController extends GetxController {
  SmartViewController({
    required this.repo,
    required this.tickets,
    required this.submissions,
    required this.newTicketDetail,
    SmartViewPrefs? prefs,
    this.files,
    this.views,
    this.inbox,
    this.tour,
  }) : prefs = prefs ?? SmartViewPrefs(),
       mode = Rx<SvViewMode>((prefs ?? SmartViewPrefs()).mode);

  final SmartViewRepository repo;
  final TicketRepository tickets;
  final SubmissionRepository submissions;
  final TicketDetailController Function(int id) newTicketDetail;
  final SmartViewPrefs prefs;

  /// Fetches the files of records for the viewer; null: no file viewer.
  final SvFileRepository? files;

  /// The saved views of the open structure; null: no tabs.
  final SvSavedViewsRepository? views;

  /// Who reports to the person (`records.people`) and their names and
  /// pictures (`people.cards`), for the "My team" line; null: no team lines.
  final InboxRepository? inbox;

  /// The first-run tour; null where tours are not set up.
  final SmartViewTour? tour;

  bool get hasFiles => files != null;

  SvFilePreviewController newFilePreview(List<SvFile> list, int index) =>
      SvFilePreviewController(files: list, repo: files!, index: index);

  /// Cards or Table, the app-wide choice (restored before the first frame).
  final Rx<SvViewMode> mode;

  /// Records whose card shows every field; kept for the session, by id.
  final expanded = <int>{}.obs;

  /// Records whose file list is open past the first three (this session).
  final filesExpanded = <int>{}.obs;

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
  final _states = <String, SvViewState>{};
  final _selected = <String, String?>{};
  final _loadedViews = <String, SvViewsLoad>{};

  /// The group levels, column layout and view of the open structure, with
  /// [query] the working state a saved view is compared against.
  final groupBy = <String>[].obs;
  final hidden = <String>[].obs;
  final order = <String>[].obs;
  final baseline = Rx<SvViewState>(SvViewState.plain);
  final tabs = <SvSavedView>[].obs;
  final sharedTabs = <SvSavedView>[].obs;
  final storedDefault = Rxn<SvSavedView>();
  final viewsPhase = SvViewsPhase.loading.obs;

  /// The selected tab's id; null is the Default View.
  final selectedViewId = Rxn<String>();
  final isSavingViews = false.obs;

  /// Counts page switches (mode or view); only the newest page of the mode
  /// switcher holds the tour's card key.
  final pageSeq = 0.obs;

  /// False once the server refused a save: "+" and the manage actions hide.
  final canWriteViews = true.obs;
  final _closed = <String, RxSet<String>>{};

  /// Asked when the target view changed on another device: true overwrites,
  /// false reloads. Set by the screen.
  Future<bool> Function()? askOverwrite;
  Timer? _searchTimer;
  String? _inputSource;
  List<SvRow> _inputRows = const [];
  SvEngineInput? _input;
  int _dataVersion = 0;
  ({int data, SmartViewQuery query})? _shownKey;
  List<SvRow> _shown = const [];
  DateTime Function() clock = DateTime.now;
  final _details = <int, TicketDetailController>{};
  bool _isListRead = false;

  SvSource? get source => table.value?.source;

  /// The structures matching the Find text (name or caption, any case).
  List<SvSource> get shownSources {
    final sample = _sampleSource;
    if (sample != null) return [sample];
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
    CrashBreadcrumbs.add(
      value == SvViewMode.table
          ? Crumb.smartviewModeTable
          : Crumb.smartviewModeCards,
    );
    fireAndLog('smart_view_controller', () => prefs.setMode(value));
  }

  void toggleFilesExpanded(int id) {
    if (!filesExpanded.remove(id)) filesExpanded.add(id);
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

  /// Every way in. The tab alone: the view that was open, else the list with
  /// the drawer open. `#view`: the list. `#view <name>`: that view (read
  /// afresh), the drawer closed.
  Future<void> enter(SmartViewEntry entry) async {
    CrashBreadcrumbs.add(Crumb.smartviewOpen);
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

  /// Back: the drawer closes first, then the screen is left.
  bool get canLeave => !(isActive.value && isDrawerOpen.value);

  void onBack() {
    if (isDrawerOpen.value) closeDrawer();
  }

  /// Reads the structures once; [isForced] reads them again (Retry).
  Future<void> loadList({bool isForced = false}) async {
    if (_isListRead && !isForced) return;
    if (sources.isEmpty || !isForced) listPhase.value = SvPhase.loading;
    try {
      final all = SvSources.sorted(await repo.sources(isForced: isForced));
      sources.assignAll(all);
      listPhase.value = all.isEmpty ? SvPhase.empty : SvPhase.ready;
      _isListRead = true;
    } on SocketCallError catch (e) {
      if (sources.isEmpty) {
        listPhase.value = e.isConnectionGap ? SvPhase.offline : SvPhase.error;
      } else {
        listPhase.value = SvPhase.ready;
      }
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
    if (_demo?.isSampleSource(s) ?? false) return;
    if (current.value?.name == s.name && table.value != null) return;
    _closeTable();
    _restoreQuery(s.name);
    current.value = s;
    final t = repo.open(s);
    t.team = query.value.team;
    table.value = t;
    fireAndLog('smart_view_controller', () => _loadViews(s));
    _learnMembers();
    await repo.load(t);
  }

  void _closeTable() {
    final t = table.value;
    if (t != null && !(_demo?.isSampleTable(t) ?? false)) repo.close(t);
    for (final d in _details.values) {
      d.onClose();
    }
    _details.clear();
    table.value = null;
  }

  // ---- search, filter, sort: one query per view, cards and table alike ----

  void _restoreQuery(String name) {
    _searchTimer?.cancel();
    final st = _states[name] ?? SvViewState.plain;
    query.value = st.query;
    groupBy.assignAll(st.groupBy);
    hidden.assignAll(st.hidden);
    order.assignAll(st.order);
    searchField.text = st.query.search;
    isSearchOpen.value = st.query.search.isNotEmpty;
    selectedViewId.value = _selected[name];
    final l = _loadedViews[name];
    if (l == null) {
      _clearViews();
    } else {
      _showViews(l);
    }
    baseline.value = _baselineFor(name, selectedViewId.value);
  }

  void _clearViews() {
    tabs.clear();
    sharedTabs.clear();
    storedDefault.value = null;
    selectedViewId.value = null;
    baseline.value = SvViewState.plain;
    viewsPhase.value = SvViewsPhase.loading;
  }

  void _showViews(SvViewsLoad l) {
    tabs.assignAll(l.tabs);
    sharedTabs.assignAll(l.shared);
    storedDefault.value = l.stored;
    viewsPhase.value = SvViewsPhase.ready;
  }

  void setQuery(SmartViewQuery q, {bool isLogged = false}) {
    final before = query.value;
    query.value = q;
    if (q.isFiltering && q != before) {
      CrashBreadcrumbs.add(Crumb.smartviewFilterApplied);
    }
    _keep();
    _syncTeam();
    if (isLogged) _logQuery(before, q);
  }

  // ---- "My team" and "Linked as" ----

  /// The person's direct reports (user names); empty until known or when
  /// nobody reports to them, and then the two lines are not drawn.
  final teamUsers = <String>[].obs;
  bool _isTeamRead = false;

  /// The choices the filter panel draws; null when this tab has no Inbox data
  /// layer to ask.
  late final SvTeamChoices? teamChoices = inbox == null
      ? null
      : SvTeamChoices(
          users: teamUsers,
          nameOf: teamNameOf,
          pictureOf: teamPictureOf,
        );

  String teamNameOf(String user) {
    inbox?.cardRevision.value;
    final name = inbox?.cardOf(user)?.name.trim() ?? '';
    return name.isEmpty ? user : name;
  }

  String? teamPictureOf(String user) {
    inbox?.cardRevision.value;
    final a = inbox?.cardOf(user)?.avatar ?? '';
    return a.isEmpty ? null : a;
  }

  /// Reads who reports to the person once per session (`records.people`
  /// through the shared gate; the Inbox's answer is reused). A failed read is
  /// nobody: the lines stay hidden and the next panel opening asks again.
  Future<void> loadTeam() async {
    final r = inbox;
    if (r == null || _isTeamRead) return;
    try {
      final known = r.people.last.value;
      final people = known ?? await r.loadPeople();
      if (people == null) return;
      _isTeamRead = true;
      teamUsers.assignAll(people.team);
      await r.loadCards(people.team);
    } on SocketCallError catch (e, st) {
      AppLog.e('smart_view_controller', e, st, 'records.people failed');
    }
  }

  /// Names and pictures of the members a condition names (a view saved on the
  /// web may name people the panel never listed).
  void _learnMembers() {
    final names = SvTeam.membersOf(query.value.conditions);
    final r = inbox;
    if (r == null || names.isEmpty) return;
    fireAndLog('smart_view_controller', () => r.loadCards(names));
  }

  /// The open table is read by the query's team lines; a change reads again.
  void _syncTeam() {
    final t = table.value;
    if (t == null) return;
    final want = query.value.team;
    if (t.team == want) return;
    _learnMembers();
    fireAndLog('smart_view_controller', () => _readTeam(t, want));
  }

  Future<void> _readTeam(SvTable t, SvTeamFilter? want) async {
    await repo.applyTeam(t, want);
    if (table.value != t || t.team != want) return;
    if (t.hasPartialError.value && t.errorMessage.value.isNotEmpty) {
      AppNotices.warning(t.errorMessage.value);
    }
  }

  /// The working state of the open structure, kept for the session.
  SvViewState get working => SvViewState(
    query: query.value,
    groupBy: groupBy.toList(),
    hidden: hidden.toList(),
    order: order.toList(),
  );

  void _keep() {
    final name = current.value?.name;
    if (name == null) return;
    _states[name] = working;
    _selected[name] = selectedViewId.value;
  }

  /// One `[records]` line for an Apply, a removed chip or a Clear: how many
  /// filters and of what kind (column type and operator, never names or
  /// values), how many rows before and after, and whether the result was
  /// already held.
  void _logQuery(SmartViewQuery before, SmartViewQuery after) {
    if (!kDebugMode) return;
    final view = current.value?.name;
    final input = engineInput;
    if (view == null || input == null) return;
    final active = after.activeConditions;
    final kinds = [
      for (final c in active)
        '${input.columns.columns.where((x) => x.key == c.col).firstOrNull?.type.name ?? 'unknown'}/${c.op}',
    ];
    int count(SmartViewQuery q) => q.isFiltering || q.isSorting
        ? input.apply(q, now: clock()).length
        : input.rows.length;
    final from = count(before);
    final isHit =
        !(after.isFiltering || after.isSorting) ||
        _shownKey == (data: _dataVersion, query: after);
    RecordsLog.line(
      'smartview query view=$view filters=${active.length} '
      'kinds=[${kinds.join(', ')}] rows=$from->${count(after)} '
      'cache=${isHit ? 'hit' : 'miss'}',
    );
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

  /// Commits exactly [list] (a replacement, never a merge). A copy is kept,
  /// so a caller that goes on editing its list cannot change the query.
  void setConditions(List<SvCondition> list) => setQuery(
    query.value.copyWith(conditions: List<SvCondition>.unmodifiable(list)),
    isLogged: true,
  );

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
    setQuery(
      query.value.copyWith(search: '', conditions: const []),
      isLogged: true,
    );
  }

  /// Everything off: search, scope, filters and sort ("Clear").
  void clearQuery() {
    _searchTimer?.cancel();
    searchField.clear();
    setQuery(SmartViewQuery.none, isLogged: true);
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

  /// The engine's input for the loaded rows, built once per data version (a
  /// new version whenever the structure or any row object changes). Reads the
  /// table reactively, so an Obx that calls it follows new pages.
  SvEngineInput? get engineInput {
    final t = table.value;
    if (t == null) return null;
    final rows = t.rows.toList();
    if (_input == null ||
        _inputSource != t.source.name ||
        !_sameRows(_inputRows, rows)) {
      _inputSource = t.source.name;
      _inputRows = rows;
      _dataVersion++;
      _input = SvEngineInput.of(SmartViewColumns.of(t.source), rows);
    }
    return _input;
  }

  static bool _sameRows(List<SvRow> a, List<SvRow> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// The rows both Cards and Table draw: the loaded rows through the query.
  /// The result is kept for one (data version, query) pair, compared by
  /// value, never by a hash alone.
  List<SvRow> get shownRows {
    final t = table.value;
    if (t == null) return const [];
    final q = query.value;
    if (!q.isFiltering && !q.isSorting) {
      _shownKey = null;
      return t.rows.toList();
    }
    final input = engineInput!;
    final key = (data: _dataVersion, query: q);
    if (_shownKey != key) {
      _shown = input.apply(q, now: clock());
      _shownKey = key;
    }
    return _shown;
  }

  ({int data, SmartViewQuery query})? _insightKey;
  List<int> _insightRows = const [];

  /// The positions (in [engineInput]) of the rows that pass the search and
  /// filters, for the KPI and chart sheets. Worked out when a sheet asks and
  /// kept until the data or the query changes; nothing runs while they are
  /// closed.
  List<int> get insightRows {
    final input = engineInput;
    if (input == null) return const [];
    final key = (data: _dataVersion, query: query.value);
    if (_insightKey != key) {
      _insightRows = input.positions(query.value, now: clock());
      _insightKey = key;
    }
    return _insightRows;
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
    if (_demo?.isSampleTable(t) ?? false) return;
    if (t == null) {
      await loadList(isForced: true);
    } else {
      await repo.refresh(t);
    }
  }

  /// The structure's add form (`tstruct.user.open`, as `#tstruct-add`), then
  /// back here: the saved record shows when the server has it.
  Future<void> add() async {
    if (_demo?.isSampleSource(source) ?? false) return;
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
      if (result == true)
        fireAndLog('smart_view_controller', () => repo.refreshNewest(t));
    } finally {
      isAdding.value = false;
    }
  }

  // ---- saved views: tabs, working state, group and columns ----------------

  /// The columns the open structure draws, as the working view lays them
  /// out (hidden ones out, saved order). Never holds a structure-hidden
  /// field: those are not in the source list.
  SmartViewColumns? get shownColumns {
    final c = columns;
    if (c == null) return null;
    return c.laidOut(hidden: hidden.toList(), order: order.toList());
  }

  Set<String> get _knownKeys => {
    for (final c in columns?.listable ?? const <SvColumn>[]) c.key,
  };

  SvSavedView? viewById(String? id) {
    if (id == null) return null;
    for (final v in [...tabs, ...sharedTabs]) {
      if (v.id == id) return v;
    }
    return null;
  }

  bool get isSharedSelected =>
      selectedViewId.value != null &&
      sharedTabs.any((v) => v.id == selectedViewId.value);

  SvViewState _baselineFor(String name, String? id) {
    final known = _knownKeysOf(name);
    final v = id == null ? storedDefault.value : viewById(id);
    return v?.toState(known) ?? SvViewState.plain;
  }

  Set<String> _knownKeysOf(String name) {
    final s = table.value?.source;
    if (s == null || s.name != name) return _knownKeys;
    return {for (final c in SmartViewColumns.of(s).listable) c.key};
  }

  /// The working state differs from the selected view as saved (the Default
  /// View counts as the stored default, else the plain list).
  bool get isDirty => working != baseline.value;

  /// Save writes: a saved own view, changed, and the server allows it.
  bool get canSave =>
      canWriteViews.value &&
      selectedViewId.value != null &&
      !isSharedSelected &&
      !isSavingViews.value &&
      isDirty;

  bool get canManage => canWriteViews.value && views != null;

  Future<void> _loadViews(SvSource s) async {
    final r = views;
    if (r == null) {
      viewsPhase.value = SvViewsPhase.ready;
      return;
    }
    if (_loadedViews[s.name] != null) return;
    viewsPhase.value = SvViewsPhase.loading;
    try {
      final l = await r.load(s.name);
      if (current.value?.name != s.name) return;
      _loadedViews[s.name] = l;
      _showViews(l);
      final first = _states[s.name] == null;
      final def = l.stored;
      if (first && def != null && table.value != null) {
        _apply(def.toState(_knownKeys), null);
      } else {
        baseline.value = _baselineFor(s.name, selectedViewId.value);
      }
    } on SocketCallError {
      if (current.value?.name == s.name) viewsPhase.value = SvViewsPhase.error;
    }
  }

  /// Reads the saved views of [s] (the open structure; also the debug lab).
  Future<void> openViews(SvSource s) => _loadViews(s);

  Future<void> retryViews() async {
    final s = current.value;
    if (s == null) return;
    _loadedViews.remove(s.name);
    await _loadViews(s);
  }

  void _apply(SvViewState st, String? id) {
    _searchTimer?.cancel();
    query.value = st.query;
    groupBy.assignAll(st.groupBy);
    hidden.assignAll(st.hidden);
    order.assignAll(st.order);
    searchField.text = st.query.search;
    isSearchOpen.value = st.query.search.isNotEmpty;
    selectedViewId.value = id;
    baseline.value = st;
    _keep();
    _syncTeam();
  }

  /// A tab was tapped: that view replaces the working state (null: the
  /// Default View).
  void selectView(String? id) {
    final name = current.value?.name;
    if (name == null) return;
    if (id == selectedViewId.value) return;
    final st = _baselineFor(name, id);
    _apply(st, id);
  }

  /// Back to the selected view as saved.
  void resetToSaved() => _apply(baseline.value, selectedViewId.value);

  String _newId() => clock().microsecondsSinceEpoch.toString();

  Future<bool> saveCurrent() async {
    final v = viewById(selectedViewId.value);
    if (v == null || !canSave) return false;
    final ok = await _commit(
      SvViewChange.update(v.withState(working)),
      seen: v,
    );
    if (ok) {
      baseline.value = working;
      AppNotices.success('View updated');
    }
    return ok;
  }

  /// Creates a view from the working state (Save as new view and Create
  /// view: the web starts "Create view" from a plain list, on a phone both
  /// start from what is on screen).
  Future<bool> saveAsNew(String rawName) async {
    final name = SvSavedView.cleanName(rawName);
    final v = SvSavedView.fresh(_newId(), name, working);
    final ok = await _commit(SvViewChange.add(v));
    if (ok) {
      selectedViewId.value = v.id;
      baseline.value = working;
      _keep();
    }
    return ok;
  }

  Future<bool> renameView(String id, String rawName) async {
    final v = viewById(id);
    if (v == null) return false;
    return _commit(
      SvViewChange.update(v.copyWith(name: SvSavedView.cleanName(rawName))),
      seen: v,
    );
  }

  Future<bool> duplicateView(String id) async {
    final v = viewById(id);
    if (v == null) return false;
    var name = SvSavedView.cleanName('${v.name} copy');
    var n = 2;
    while (tabs.any((x) => x.name.toLowerCase() == name.toLowerCase())) {
      name = SvSavedView.cleanName('${v.name} copy $n');
      n++;
    }
    return _commit(
      SvViewChange.add(
        SvSavedView(
          id: _newId(),
          name: name,
          search: v.search,
          filters: v.filters,
          sortCol: v.sortCol,
          sortDir: v.sortDir,
          groupBy: v.groupBy,
          hidden: v.hidden,
          order: v.order,
          widths: v.widths,
          kpis: v.kpis,
          charts: v.charts,
          extra: v.extra,
        ),
      ),
    );
  }

  Future<bool> deleteView(String id) async {
    final v = viewById(id);
    if (v == null) return false;
    final wasSelected = selectedViewId.value == id;
    final ok = await _commit(SvViewChange.remove(id), seen: v);
    if (ok && wasSelected) {
      _apply(_baselineFor(current.value!.name, null), null);
    }
    return ok;
  }

  Future<bool> _commit(
    SvViewChange change, {
    SvSavedView? seen,
    bool isOverwrite = false,
  }) async {
    final r = views;
    final s = current.value;
    if (r == null || s == null) return false;
    isSavingViews.value = true;
    try {
      final out = await r.apply(
        s.name,
        change,
        seen: seen,
        isOverwrite: isOverwrite,
      );
      if (current.value?.name != s.name) return false;
      switch (out.status) {
        case SvSaveStatus.saved:
          final l = SvViewsLoad(mine: out.views, shared: sharedTabs.toList());
          _loadedViews[s.name] = l;
          _showViews(l);
          return true;
        case SvSaveStatus.conflict:
          final overwrite = await askOverwrite?.call() ?? false;
          if (overwrite) {
            return _commit(change, seen: seen, isOverwrite: true);
          }
          await _reloadAfterConflict(s);
          return false;
        case SvSaveStatus.offline:
          AppNotices.warning('Needs a connection');
        case SvSaveStatus.forbidden:
          canWriteViews.value = false;
          AppNotices.warning("You can't save views here.");
        case SvSaveStatus.readFailed:
          AppNotices.error("Couldn't check your views. Nothing was saved.");
        case SvSaveStatus.invalid:
          AppNotices.warning(out.message);
        case SvSaveStatus.writeFailed:
          AppNotices.error("Your views couldn't be saved. Try again.");
      }
      return false;
    } finally {
      isSavingViews.value = false;
    }
  }

  Future<void> _reloadAfterConflict(SvSource s) async {
    _loadedViews.remove(s.name);
    final id = selectedViewId.value;
    await _loadViews(s);
    if (id != null && viewById(id) != null) {
      _apply(_baselineFor(s.name, id), id);
    } else if (id != null) {
      _apply(_baselineFor(s.name, null), null);
    }
  }

  /// The group levels (the web's keys, outer first), at most five.
  void setGroupBy(List<String> keys) {
    groupBy.assignAll(keys.take(SvViewLimits.maxGroups));
    _closed[_closedKey]?.clear();
    _keep();
  }

  /// Column choices from the editor: [hiddenKeys] and [orderKeys] are the
  /// web's keys. Entries for columns this editor cannot show (kept in a
  /// saved view) are carried over untouched.
  void setColumns(List<String> hiddenKeys, List<String> orderKeys) {
    hidden.assignAll(hiddenKeys);
    order.assignAll(orderKeys);
    _keep();
  }

  String get _closedKey =>
      '${current.value?.name ?? ''}|${selectedViewId.value ?? ''}';

  /// Collapsed groups of the selected view (kept per view, this session).
  RxSet<String> get closedGroups =>
      _closed.putIfAbsent(_closedKey, () => <String>{}.obs);

  void toggleGroup(String path) {
    final set = closedGroups;
    if (!set.remove(path)) set.add(path);
  }

  ({int data, SmartViewQuery query, String keys, String closed})? _groupKey;
  SvGrouped? _grouped;

  /// The shown rows grouped by the working levels (null: no grouping).
  /// Search and filters first, then sort, then the groups, as the web does;
  /// each header holds the row count and the total of the first measure
  /// column.
  SvGrouped? get grouped {
    final cols = shownColumns;
    final input = engineInput;
    if (input == null || cols == null) return null;
    final keys = [
      for (final g in groupBy)
        if (cols.columns.any((c) => c.key == SvKeys.mobile(g)) &&
            input.col(SvKeys.mobile(g)) != null)
          SvKeys.mobile(g),
    ];
    if (keys.isEmpty) return null;
    final q = query.value;
    final closed = closedGroups.toList()..sort();
    final key = (
      data: _dataVersion,
      query: q,
      keys: keys.join('\u001f'),
      closed: closed.join('\u001e'),
    );
    if (_groupKey == key && _grouped != null) return _grouped;
    final pos = input.orderedPositions(q, now: clock());
    final sumKey = input.measureKeys.firstOrNull;
    final all = SvEngine.group(input.table, pos, keys, sumKey: sumKey);
    final index = <int, int>{};
    final rows = <SvRow>[];
    for (final f in all) {
      if (!f.isGroup) {
        index[f.row!] = rows.length;
        rows.add(input.rows[f.row!]);
      }
    }
    final flat = [
      for (final f in SvEngine.group(
        input.table,
        pos,
        keys,
        sumKey: sumKey,
        closed: closedGroups.toSet(),
      ))
        f.isGroup ? f : SvFlat.row(index[f.row!]!, f.depth),
    ];
    String? label;
    if (sumKey != null) {
      label = cols.columns
          .followedBy(columns!.columns)
          .firstWhere((c) => c.key == sumKey)
          .label;
    }
    _groupKey = key;
    return _grouped = SvGrouped(rows, flat, label);
  }

  // ---- the card's bar and menu: the queue's, nothing new per card ---------

  /// The menu is opened: its actions are read once (cached 60 s).
  void openRecordMenu(int id) =>
      fireAndLog('smart_view_controller', () => tickets.ensureMenu(id));

  TicketDetailController detailOf(int id) => _details.putIfAbsent(id, () {
    final c = newTicketDetail(id);
    c.onInit();
    return c;
  });

  // ---- first-run tour ----------------------------------------------------------

  late final TourTrigger _tourTrigger = TourTrigger(
    canTry: _canTryTour,
    start: _startTour,
  );
  final _tourWorkers = <Worker>[];
  Worker? _phaseWorker;

  @override
  void onInit() {
    super.onInit();
    if (tour == null) return;
    void schedule() => _tourTrigger.schedule();
    _tourWorkers.addAll([
      ever(mode, (_) => pageSeq.value++),
      ever(selectedViewId, (_) => pageSeq.value++),
      ever(isActive, (on) {
        if (on) {
          schedule();
        } else {
          _tourTrigger.cancel();
          tour?.cancel();
        }
      }),
      ever(isDrawerOpen, (open) {
        if (_demo?.isDriving ?? false) return;
        if (tour?.isRunning ?? false) {
          tour?.cancel();
        } else {
          schedule();
        }
      }),
      ever(listPhase, (_) => schedule()),
      ever(table, (t) {
        _phaseWorker?.dispose();
        _phaseWorker = t == null ? null : ever(t.phase, (_) => schedule());
        schedule();
      }),
    ]);
  }

  SvTourDemo? get _demo => tour?.demo;

  /// The sample view the drawer lists while the tour runs, only when the
  /// person has no view of their own (a real list always wins).
  SvSource? get _sampleSource {
    final d = _demo;
    if (d == null || !d.isListSample.value || sources.isNotEmpty) return null;
    return d.source;
  }

  /// What the drawer's list shows: the sample view counts as a ready list.
  SvPhase get drawerPhase =>
      _sampleSource != null ? SvPhase.ready : listPhase.value;

  /// The records on screen are the tour's sample ones.
  bool get isTourSampleShown {
    final t = table.value;
    return _demo?.isSampleTable(t) ?? false;
  }

  /// The tour needs the list read, and a view that is open to have been read
  /// to its end (loading or failed states are not shown a tour over).
  bool get _isTourReady {
    final t = table.value;
    if (t == null) {
      return listPhase.value == SvPhase.ready ||
          listPhase.value == SvPhase.empty;
    }
    return t.phase.value == SvPhase.ready || t.phase.value == SvPhase.empty;
  }

  bool get _hasRealList =>
      listPhase.value == SvPhase.ready && sources.isNotEmpty;

  bool get _hasRealRows {
    final t = table.value;
    return t != null && t.rows.isNotEmpty;
  }

  bool _canTryTour() =>
      tour != null &&
      !isClosed &&
      isActive.value &&
      !isSearchOpen.value &&
      _isTourReady;

  /// Some record on screen has a file (the first rows are enough).
  bool get _hasFilesForTour {
    final t = table.value;
    if (t == null || !hasFiles) return false;
    final columns = shownColumns ?? SmartViewColumns.of(t.source);
    return shownRows
        .take(30)
        .any(
          (r) => columns.cardOf(r).fields.any((f) => f.cell.files.isNotEmpty),
        );
  }

  Future<TourStart> _startTour() async {
    final tour = this.tour;
    if (tour == null || isClosed || !_isTourReady) return TourStart.failed;
    await WidgetsBinding.instance.endOfFrame;
    if (isClosed) return TourStart.failed;
    _tourStartedOpen = isDrawerOpen.value;
    return tour.start(
      _tourPorts,
      isSample: !_hasRealList || !_hasRealRows,
      hasFiles: _hasFilesForTour || !_hasRealRows,
      isDrawerOpen: _tourStartedOpen,
    );
  }

  /// The drawer as the tour found it (the list opens it by itself when no
  /// view is selected); every way a tour ends puts it back like that.
  bool _tourStartedOpen = false;

  late final SvTourPorts _tourPorts = SvTourPorts(
    seed: _seedTour,
    restore: _restoreTour,
    openDrawer: () => isDrawerOpen.value = true,
    closeDrawer: () => isDrawerOpen.value = false,
    pick: _tourPick,
    unpick: _tourUnpick,
    expandFirst: () => _tourExpand(true),
    collapseFirst: () => _tourExpand(false),
    openFilter: () => _demo?.isFilterOpen.value = true,
    closeFilter: () => _demo?.isFilterOpen.value = false,
  );

  /// Real data first: the sample view only without views, the sample records
  /// only when no open view has records.
  bool _seedTour() {
    final d = _demo;
    if (d == null) return false;
    final isList = !_hasRealList;
    final isRecords = !_hasRealRows;
    d.begin(
      isList: isList,
      isRecords: isRecords,
      now: DateTime.now().millisecondsSinceEpoch,
    );
    return isList || isRecords;
  }

  /// The drawer closed, the open view back, the sample gone. Runs on every
  /// way a tour ends, and more than once.
  void _restoreTour() {
    _tourUnpick();
    isDrawerOpen.value = isActive.value && _tourStartedOpen;
    _demo?.end();
  }

  /// Shows the records: the sample ones when no real view has records, in
  /// cards (the saved mode is only restored, never written to preferences).
  void _tourPick() {
    final d = _demo;
    if (d == null || d.saved != null) return;
    d.saved = SvTourSaved(
      table: table.value,
      current: current.value,
      query: query.value,
      groupBy: groupBy.toList(),
      hidden: hidden.toList(),
      order: order.toList(),
      selectedViewId: selectedViewId.value,
      mode: mode.value,
    );
    if (mode.value != SvViewMode.cards) mode.value = SvViewMode.cards;
    final sample = d.table;
    if (d.isRecordsSample.value && sample != null && !_hasRealRows) {
      query.value = SmartViewQuery.none;
      groupBy.clear();
      hidden.clear();
      order.clear();
      selectedViewId.value = null;
      current.value = d.source;
      table.value = sample;
    }
  }

  void _tourUnpick() {
    final d = _demo;
    final saved = d?.saved;
    if (d == null || saved == null) return;
    d.saved = null;
    d.isFilterOpen.value = false;
    expanded.removeWhere((id) => id < 0);
    filesExpanded.removeWhere((id) => id < 0);
    if (d.isSampleTable(table.value)) {
      table.value = saved.table;
      current.value = saved.current;
      query.value = saved.query;
      groupBy.assignAll(saved.groupBy);
      hidden.assignAll(saved.hidden);
      order.assignAll(saved.order);
      selectedViewId.value = saved.selectedViewId;
    }
    if (mode.value != saved.mode) mode.value = saved.mode;
  }

  /// The first card on screen opens (every field and the files) or closes.
  void _tourExpand(bool isOpen) {
    final d = _demo;
    if (d == null) return;
    final id = isOpen ? shownRows.firstOrNull?.id : _tourExpandedId;
    if (id == null) return;
    if (isOpen) {
      _tourExpandedId = id;
      if (expanded.add(id)) filesExpanded.add(id);
    } else {
      _tourExpandedId = null;
      expanded.remove(id);
      filesExpanded.remove(id);
    }
  }

  int? _tourExpandedId;

  @override
  void onClose() {
    _tourTrigger.dispose();
    for (final w in _tourWorkers) {
      w.dispose();
    }
    _phaseWorker?.dispose();
    tour?.cancel();
    _searchTimer?.cancel();
    _closeTable();
    searchField.dispose();
    findField.dispose();
    super.onClose();
  }
}
