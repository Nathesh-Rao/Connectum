import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../core/log/safe.dart';
import '../../core/tour/tour_service.dart';
import '../../core/tour/tour_trigger.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/approval.dart';
import '../../data/models/record_live.dart';
import '../../data/records/record_commands.dart';
import '../../data/repositories/inbox_field_kinds.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/sv_file_repository.dart';
import '../../data/smart_view/sv_file.dart';
import '../smart_view/sv_file_preview_controller.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../home_shell/home_shell_controller.dart';
import '../home_shell/home_tab.dart';
import '../tickets/ticket_detail_controller.dart';
import 'inbox_approvals_controller.dart';
import 'inbox_filter_controller.dart';
import 'inbox_live.dart';
import 'inbox_tour.dart';
import 'inbox_tour_demo.dart';
import 'inbox_views_controller.dart';
import 'models/approval_entries.dart';
import 'models/inbox_approval_rows.dart';
import 'models/inbox_filter.dart';
import 'models/inbox_filter_chips.dart';
import 'models/inbox_page.dart';
import 'models/inbox_query.dart';
import 'models/inbox_row.dart';
import 'models/inbox_saved_view.dart';
import 'models/inbox_sort.dart';
import 'models/inbox_tab.dart';
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
    this.files,
    this.tour,
    DateTime Function()? now,
    this.liveEvents,
    this.liveOnline,
    DateTime Function()? liveNow,
    this.liveDebounce = const Duration(milliseconds: 300),
    this.liveGap = const Duration(seconds: 2),
  }) : _now = now ?? DateTime.now,
       _liveNow = liveNow;

  static const title = 'Inbox';
  static const searchHint = 'Search records';
  static const searchNote = 'Searching loaded records';
  static const emptyTitle = 'No records yet.';
  static const noMatchTitle = 'No records match your search.';
  static const noFilterMatchTitle = 'No records match the filter.';
  static const errorText =
      'The records could not be read. Pull down to try again.';
  static const approvalsHeading = 'Approvals';
  static const approvalsLoadingText = 'Reading approvals...';
  static const approvalsErrorText =
      'The approvals could not be read. Pull down to try again.';
  static const pageSize = RecordLimits.queryPageSize;
  static const _moreAt = 600.0;
  static const _staleAfter = Duration(seconds: 30);

  final InboxRepository inbox;
  final TicketRepository tickets;
  final SessionStore store;
  final ConnectivityService connectivity;
  final HomeShellController shell;

  /// The first-run tour; null where tours are not set up.
  final InboxTour? tour;
  final TicketDetailController Function(int id) newTicketDetail;

  /// The field kinds of the Advanced filter's conditions; read only when the
  /// panel needs them.
  final InboxFieldKinds fieldKinds;

  /// The Approvals pane (its list, filter and answers).
  final InboxApprovals approvals;

  /// The saved views (the list, the open view, what was last saved).
  final InboxViews views;

  /// Fetches files for the Smart View file preview when a file chip is
  /// tapped; null: the chip is plain.
  final SvFileRepository? files;

  bool get hasFiles => files != null;

  SvFilePreviewController newFilePreview(List<SvFile> list, int index) =>
      SvFilePreviewController(files: list, repo: files!, index: index);

  /// The type of a field of a row's form when the source list is already held
  /// (never read for this); null otherwise.
  String? fieldTypeOf(InboxRow r, String field) =>
      fieldKinds.typeOf(r.formId, field);
  final DateTime Function() _now;

  /// The socket's events and its "connected again" signal, for the live
  /// re-read. Null: no live updates.
  final Stream<Map<String, dynamic>>? liveEvents;
  final Stream<void>? liveOnline;
  final DateTime Function()? _liveNow;
  final Duration liveDebounce;
  final Duration liveGap;

  late final InboxLive live = InboxLive(
    state: _liveState,
    isBusy: () => isRefreshing.value || isLoadingMore.value,
    read: _liveRead,
    now: _liveNow,
    debounce: liveDebounce,
    minGap: liveGap,
  );
  final _liveSubs = <StreamSubscription<dynamic>>[];
  InboxFilterController? _panel;

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

  /// The tab shown (an index of [InboxTabs.all]). Never saved.
  final tabIndex = 0.obs;

  /// The Approvals tab is shown.
  bool get isApprovalsOpen =>
      tabIndex.value == InboxTabs.indexOf(InboxTab.approvals);

  /// The search text of the Approvals tab; [query] is the Records tab's.
  final approvalsQuery = ''.obs;

  /// The search bar is open in the header.
  final isSearchOpen = false.obs;

  /// "Save your changes?" is waiting for an answer (the view shows it).
  final unsavedPrompt = Rxn<UnsavedPrompt>();

  /// The person answered Save or Discard on the way out: back may leave.
  final isLeaving = false.obs;

  /// "View submission": the one record the Records tab shows under a header
  /// strip (`record.card`). [focusId] is its number while it is asked or
  /// shown; [focusRow] is null until it was read.
  final focusId = Rxn<int>();
  final focusRow = Rxn<InboxRow>();
  bool get isFocused => focusId.value != null;

  final _workers = <Worker>[];
  final _details = <int, TicketDetailController>{};
  int _ask = 0;
  int _focusAsk = 0;
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
      ever(approvalsQuery, (t) => approvals.paneQuery.value = t),
      ever(shell.approvalsRequest, (_) => _takeApprovalsRequest()),
      ever(shell.recordRequest, (_) => _takeRecordRequest()),
      ever(shell.listRequest, (_) => _takeListRequest()),
      ever(approvals.approvals.all, (_) => _update()),
      ever(approvals.approvals.hasRead, (_) => _update()),
      ever(approvals.approvals.hasError, (_) => _update()),
      ever(shell.tab, (t) {
        if (t == HomeTab.inbox) {
          _enter();
          _tourTrigger.schedule();
        } else {
          _tourTrigger.cancel();
          tour?.cancel();
        }
      }),
      ever(viewState, (_) => _tourTrigger.schedule()),
      ever(tabIndex, (_) {
        if (_demo?.isDriving ?? false) return;
        if (isApprovalsOpen) tour?.cancel();
        _tourTrigger.schedule();
      }),
      ever(isSearchOpen, (_) => _tourTrigger.schedule()),
      ever(focusId, (_) => _tourTrigger.schedule()),
      ever(connectivity.state, (s) {
        if (s == AppConnectivity.online && _isEntered && _needsRead) {
          fireAndLog('inbox_controller', () => load());
        }
      }),
      ever(store.current, (_) => _onSession()),
    ]);
    live.start();
    final events = liveEvents;
    if (events != null) {
      _liveSubs.add(
        events.listen(live.onEvent, onError: streamOnError('inbox_controller')),
      );
    }
    final online = liveOnline;
    if (online != null) {
      _liveSubs.add(
        online.listen(
          (_) => live.onReconnect(),
          onError: streamOnError('inbox_controller'),
        ),
      );
    }
    searchFocus.addListener(() => isSearchFocused.value = searchFocus.hasFocus);
    scroll.addListener(_onScroll);
    if (shell.tab.value == HomeTab.inbox) _enter();
    _takeApprovalsRequest();
    _takeRecordRequest();
    _takeListRequest();
  }

  bool get isOnline => connectivity.state.value == AppConnectivity.online;

  /// The person looking, lower case.
  String get me => (store.userId ?? '').toLowerCase();

  bool get _needsRead => page.value == null || hasError.value;

  /// "My Team" is offered only to a person who has reports.
  bool get isTeamShown => (counts.value?.reports ?? 0) > 0;

  /// What the header says about the list: "12 records", "1000+ records",
  /// and with approvals under them "12 records, 3 approvals".
  String get totalLabel {
    final p = page.value;
    if (p == null) return '';
    final records = isRecordsOff ? '' : _recordsLabel(p);
    final n = _approvalCount;
    final approvalsText = n > 0
        ? '$n ${n == 1 ? 'approval' : 'approvals'}'
        : '';
    return [records, approvalsText].where((t) => t.isNotEmpty).join(', ');
  }

  /// The Records tab's pill: the (filtered) total of the records alone, "N+"
  /// when capped; empty before the first read or when no record is asked for.
  String get recordsCountLabel {
    final p = page.value;
    if (p == null || isRecordsOff) return '';
    return p.isCapped ? '${counts.value?.cap ?? 1000}+' : '${p.total}';
  }

  /// The tab's count pill: the records' total on Records, and on Approvals
  /// the number the quick filter's "All" status shows for the current scope
  /// (0 included).
  String pillOf(InboxTab t) =>
      t == InboxTab.records ? recordsCountLabel : _approvalsPill;

  String get _approvalsPill {
    final n =
        approvals.statusCountsFor(
          approvals.effectiveSide,
        )[ApprovalPrimary.all] ??
        0;
    return n > 9999 ? '9999+' : '$n';
  }

  String _recordsLabel(InboxPage p) {
    final n = p.isCapped ? '${counts.value?.cap ?? 1000}+' : '${p.total}';
    return '$n ${p.total == 1 && !p.isCapped ? 'record' : 'records'}';
  }

  int get _approvalCount => _plan.wantsApprovals ? approvalCards.length : 0;

  /// The loaded records that match the search.
  List<InboxRow> get rows =>
      sortInboxRows(_matching(page.value?.rows ?? const []), filter.value.sort);

  InboxApprovalRows get _plan => InboxApprovalRows(filter.value);

  /// Does "Search in" name only approvals (no record is asked for, the web's
  /// `recordsOff`)?
  bool get isRecordsOff =>
      filter.value.wheres.isNotEmpty && filter.value.serverViews(_team).isEmpty;

  /// Is one approval entry the choice (a list of approvals alone)?
  bool get isApprovalList => _plan.isStageList;

  /// The approvals drawn under the records (or alone), as the filter says.
  List<Approval> get approvalCards => approvals.cardsFor(filter.value);

  /// Does the list have an approvals part?
  bool get hasApprovalsPart => _plan.wantsApprovals;

  /// Is the approvals part still being read for the first time?
  bool get isApprovalsLoading =>
      hasApprovalsPart && !approvals.isRead && !approvals.hasFailedRead;

  /// Did the first read of the approvals fail (the part says so, with Retry)?
  bool get isApprovalsFailed => hasApprovalsPart && approvals.hasFailedRead;

  /// A later read failed: the rows stay and the header says so.
  bool get isApprovalsStale =>
      hasApprovalsPart && approvals.isRead && approvals.hasError;

  bool isCardExpanded(String key) => approvals.isExpanded(key);

  void toggleCardExpanded(String key) => approvals.toggleExpanded(key);

  bool isApprovalLeaving(Approval a) => approvals.isLeavingFor(filter.value, a);

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

  /// The Records filter row: a removable chip for each filter that is on.
  List<InboxFilterChip> get filterChips {
    inbox.cardRevision.value;
    final forms = {
      for (final a in approvals.approvals.all)
        if (a.formId.isNotEmpty && a.caption.isNotEmpty) a.formId: a.caption,
      for (final e
          in (page.value?.forms ?? const <String, InboxForm>{}).entries)
        e.key: e.value.caption,
    };
    return InboxFilterChips.of(
      filter.value,
      formName: (id) => forms[id] ?? id,
      personName: (u) {
        final n = inbox.cardOf(u)?.name ?? '';
        return n.isEmpty ? u : n;
      },
    );
  }

  /// A chip's ×: the filter without that part, read again from page one.
  void removeFilterChip(InboxFilterChip chip) => applyFilter(chip.removed);

  /// The empty text: "No records match the filter." with a filter set.
  String get emptyText {
    final f = filter.value;
    if (_plan.isStageList) return _stageEmptyText;
    return f.isServerFilter || f.approvalPick.isNotEmpty
        ? noFilterMatchTitle
        : emptyTitle;
  }

  /// `No pending approvals for those forms.` (the web's words).
  String get _stageEmptyText {
    final kind = switch (_plan.stage) {
      'pending' => 'pending ',
      'approved' => 'approved ',
      'rejected' => 'rejected ',
      _ => '',
    };
    final forms = _plan.dataForms.isNotEmpty ? ' for those forms' : '';
    return 'No ${kind}approvals$forms.';
  }

  bool get hasMore => page.value?.hasMore ?? false;

  // ---- entering and leaving ----------------------------------------------------

  void _enter() {
    if (!_isEntered) {
      _isEntered = true;
      live.clearStale();
      approvals.start();
      fireAndLog('inbox_controller', () => load());
      fireAndLog('inbox_controller', () => loadViews());
      return;
    }
    if (live.isStale) {
      live.onShown();
      return;
    }
    final at = _readAt;
    if (at == null || DateTime.now().difference(at) > _staleAfter) {
      fireAndLog('inbox_controller', () => load(isSilent: true));
      fireAndLog('inbox_controller', () => approvals.reload());
    }
  }

  // ---- the Approvals pane -------------------------------------------------------

  /// The tab bar's tap: the tab becomes [i] (the view's pages follow); the search field shows that
  /// tab's own text.
  void selectTab(int i) {
    if (i < 0 || i >= InboxTabs.all.length) return;
    _showTab(i);
  }

  /// The page settled on [i] (a swipe, or the end of a tap's slide).
  void onPageChanged(int i) => _showTab(i);

  /// Exactly one list is attached: two Inbox views alive at once (a tab that
  /// is replaced while its old copy is still leaving) must not break a read.
  bool get _isScrollOne => scroll.hasClients && scroll.positions.length == 1;

  void _showTab(int i) {
    if (tabIndex.value == i) return;
    tabIndex.value = i;
    final text = _queryOf(i);
    if (searchField.text.trim() != text) searchField.text = text;
    if (text.isNotEmpty) isSearchOpen.value = true;
  }

  String _queryOf(int i) => i == InboxTabs.indexOf(InboxTab.approvals)
      ? approvalsQuery.value
      : query.value;

  /// The Approvals badge: requests that wait for this person's answer.
  int badgeOf(InboxTab t) => t == InboxTab.approvals ? approvals.count : 0;

  void openApprovals() => selectTab(InboxTabs.indexOf(InboxTab.approvals));

  /// Back to the Records tab (a filter or a saved view acts on it).
  void closeApprovals() => selectTab(InboxTabs.indexOf(InboxTab.records));

  /// A notification, the Work Space icon or a link asked for the pane.
  void _takeApprovalsRequest() {
    if (!shell.approvalsRequest.value) return;
    shell.approvalsRequest.value = false;
    approvals.clearFilters();
    openApprovals();
  }

  /// A "New submission" notification with no record number: the Records tab,
  /// the usual list.
  void _takeListRequest() {
    if (!shell.listRequest.value) return;
    shell.listRequest.value = false;
    showAllRecords();
    closeApprovals();
  }

  /// A notification's "View submission" asked for one record.
  void _takeRecordRequest() {
    final id = shell.recordRequest.value;
    if (id == null) return;
    shell.recordRequest.value = null;
    fireAndLog('inbox_controller', () => openRecord(id));
  }

  /// Shows the one record [id] on the Records tab (`record.card`). A refusal
  /// ("I cannot view it.", "No such submission.") shows the server's words
  /// and leaves the usual screen as it is.
  Future<void> openRecord(int id) async {
    if (id <= 0) return;
    closeApprovals();
    final mine = ++_focusAsk;
    focusId.value = id;
    focusRow.value = null;
    try {
      final row = await inbox.loadCard(id);
      if (mine != _focusAsk) return;
      focusRow.value = row;
      _learnPeople([row]);
    } on SocketCallError catch (e) {
      if (mine != _focusAsk) return;
      focusId.value = null;
      AppNotices.error(
        e.message.trim().isNotEmpty && !e.isConnectionGap
            ? e.message.trim()
            : 'That record could not be opened.',
      );
    }
  }

  /// "Show all records": back to the usual list and the saved view.
  void showAllRecords() {
    _focusAsk++;
    focusId.value = null;
    focusRow.value = null;
  }

  void _onSession() {
    _ask++;
    showAllRecords();
    live.cancel();
    page.value = null;
    counts.value = null;
    hasError.value = false;
    isLoadingMore.value = false;
    _readAt = null;
    _closeDetails();
    tabIndex.value = 0;
    query.value = '';
    approvalsQuery.value = '';
    searchField.clear();
    isSearchOpen.value = false;
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
    final isOff = isRecordsOff;
    if (isOff && page.value == null) {
      page.value = InboxPage.empty;
      _update();
    }
    final had = page.value;
    if (had == null && !isSilent) viewState.value = AppViewState.loading;
    isRefreshing.value = true;
    isLoadingMore.value = false;
    final shown = had?.rows.length ?? 0;
    final limit = shown.clamp(pageSize, RecordLimits.queryMaxLimit);
    try {
      final results = await Future.wait([
        isOff
            ? Future<InboxPage?>.value(InboxPage.empty)
            : inbox.query(_queryFor(scope.value), limit: limit),
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

  // ---- live re-read ---------------------------------------------------------------

  InboxLiveState _liveState() {
    if (!store.hasEnterpriseSession || !_isEntered) {
      return InboxLiveState.closed;
    }
    return shell.tab.value == HomeTab.inbox
        ? InboxLiveState.active
        : InboxLiveState.hidden;
  }

  /// A quiet read after a live event: as many records as are shown (a whole
  /// number of pages, at most 200), the counts, the approvals, and the
  /// filter panel's lists when it is open. No spinner, no scroll change. It
  /// takes no new ask number, so a read of the person's (which does) makes
  /// its answer stale; a failure keeps the list.
  Future<void> _liveRead() async {
    final had = page.value;
    if (had == null) {
      AppLog.i('inbox_live', 'no list yet, nothing to update');
      return;
    }
    final mine = _ask;
    final isOff = isRecordsOff;
    final limit = ((had.rows.length + pageSize - 1) ~/ pageSize * pageSize)
        .clamp(pageSize, RecordLimits.queryMaxLimit);
    final q = _queryFor(scope.value);
    final scopeNow = scope.value;
    Future<T?> quiet<T>(String what, Future<T?> Function() body) async {
      try {
        return await body();
      } on SocketCallError catch (e) {
        AppLog.w('inbox_live', '$what not read: ${e.code}');
      } on InboxQueryError catch (e) {
        AppLog.w('inbox_live', '$what refused: ${e.message}');
      } catch (e, st) {
        AppLog.e('inbox_live', e, st, '$what failed');
      }
      return null;
    }

    final panel = _panel;
    final results = await Future.wait<Object?>([
      isOff
          ? Future<InboxPage?>.value(null)
          : quiet('records.query', () => inbox.query(q, limit: limit)),
      quiet('records.counts', inbox.loadCounts),
      quiet('req.list', () async {
        await approvals.reload();
        return true;
      }),
      if (panel != null && !panel.isDisposed)
        quiet('facets', () async {
          panel.refreshFacets();
          return true;
        }),
    ]);
    if (mine != _ask || scopeNow != scope.value) {
      AppLog.i('inbox_live', 'answer dropped (newer read or filter)');
      return;
    }
    final c = results[1] as InboxCounts?;
    if (c != null) {
      counts.value = c;
      if (scope.value == InboxScope.team && c.reports <= 0) {
        scope.value = InboxScope.me;
        fireAndLog('inbox_controller', () => load(isSilent: true));
        return;
      }
    }
    final read = results[0] as InboxPage?;
    if (read == null) {
      if (!isOff) {
        AppLog.i('inbox_live', 'list kept (read failed or replaced)');
      }
      return;
    }
    page.value = read;
    hasError.value = false;
    _readAt = DateTime.now();
    _learnPeople(read.rows);
    _update();
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
    if (isApprovalsOpen) return approvals.reload();
    if (hasApprovalsPart) fireAndLog('inbox_controller', approvals.reload);
    if (!isOnline) {
      if (page.value == null) viewState.value = AppViewState.offline;
      return;
    }
    await load(isSilent: true);
  }

  Future<void> retry() =>
      isApprovalsOpen || isRecordsOff ? approvals.reload() : load();

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
      _showView(first.name, first.setup, keepTab: true);
    }
  }

  /// The Views button: the list is read again when online (a save from
  /// another device shows); offline the last known list stays.
  Future<void> refreshViews() async {
    if (!isOnline) return;
    await views.load();
  }

  /// [keepTab]: the Inbox just opened on the Approvals tab (a notification)
  /// and the saved view lands on the Records tab under it.
  void _showView(
    String name,
    Map<String, dynamic> saved, {
    bool keepTab = false,
  }) {
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
    if (!keepTab) closeApprovals();
    _restart(keepFocus: keepTab);
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
    final problem = await views.persist(views.openName, setup, isDefault: true);
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
    final problem = await views.persist(
      name,
      setup,
      isNew: true,
      isDefault: true,
    );
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

  /// The list is read again from the first page. A view or filter change
  /// also leaves a shown "View submission" record, except the view the Inbox
  /// opens on by itself ([keepFocus]).
  void _restart({bool keepFocus = false}) {
    if (!keepFocus && isFocused) showAllRecords();
    _ask++;
    page.value = null;
    hasError.value = false;
    isLoadingMore.value = false;
    if (_isScrollOne) scroll.jumpTo(0);
    _update();
    fireAndLog('inbox_controller', () => load());
  }

  // ---- the filter ---------------------------------------------------------------

  /// A panel for the filter, to open as a sheet. Close it with `onClose`
  /// when the sheet is gone. Facets are read only while it lives.
  InboxFilterController newFilterPanel() {
    final page = this.page.value;
    final panel = InboxFilterController(
      inbox: inbox,
      initial: filter.value,
      baseWhere: scope.value.name,
      isTeamShown: isTeamShown,
      fieldKinds: fieldKinds,
      forms: {
        for (final a in approvals.approvals.all)
          if (a.formId.isNotEmpty && a.caption.isNotEmpty) a.formId: a.caption,
        for (final e in (page?.forms ?? const <String, InboxForm>{}).entries)
          e.key: e.value.caption,
      },
      approvals: approvals,
      onApply: applyFilter,
      onClear: clearFilter,
    )..onInit();
    _panel = panel;
    return panel;
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

  /// The text typed goes to the shown tab's own search.
  void onQueryChanged(String text) {
    final t = text.trim();
    if (isApprovalsOpen) {
      approvalsQuery.value = t;
    } else {
      query.value = t;
    }
  }

  /// The shown tab's search text.
  String get activeQuery =>
      isApprovalsOpen ? approvalsQuery.value : query.value;

  /// The field is emptied (the bar stays open).
  void clearSearch() {
    searchField.clear();
    onQueryChanged('');
  }

  void openSearch() {
    isSearchOpen.value = true;
    searchFocus.requestFocus();
  }

  /// Clear, back and the close icon: the bar folds away and the shown tab's
  /// search is empty again.
  void closeSearch() {
    searchFocus.unfocus();
    clearSearch();
    isSearchOpen.value = false;
  }

  /// Search over what is loaded (`filterWork`): subject, form, state, who it
  /// is with, who raised it, the number, the captions, answers and file
  /// names.
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
            has('${r.id}') ||
            r.hasAnswerText(q))
          r,
    ];
  }

  String _nameOf(InboxRow r) => inbox.cardOf(r.who)?.name ?? '';

  void _update() {
    final p = page.value;
    if (p == null) {
      if (viewState.value != AppViewState.error &&
          viewState.value != AppViewState.offline) {
        viewState.value = AppViewState.loading;
      }
      return;
    }
    if (isRecordsOff && !approvals.isRead) {
      // No record is asked for: the approvals are the whole screen.
      viewState.value = approvals.viewState;
      return;
    }
    final all = p.rows;
    if (rows.isNotEmpty) {
      viewState.value = AppViewState.content;
      return;
    }
    // Nothing of the records matched: the approvals part (its rows, or its
    // own loading and error line) still has the list.
    if (hasApprovalsPart &&
        (approvalCards.isNotEmpty || isApprovalsLoading || isApprovalsFailed)) {
      viewState.value = AppViewState.content;
      return;
    }
    final isSearchingApprovals = hasApprovalsPart && query.value.isNotEmpty;
    viewState.value = all.isEmpty && !isSearchingApprovals
        ? AppViewState.empty
        : AppViewState.noResults;
  }

  // ---- paging -------------------------------------------------------------------

  void _onScroll() {
    if (!_isScrollOne) return;
    if (scroll.position.extentAfter < _moreAt) {
      fireAndLog('inbox_controller', () => loadMore());
    }
  }

  // A short list may not scroll at all: check again once it is drawn.
  void _checkMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isClosed || !_isScrollOne) return;
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

  // ---- first-run tour ----------------------------------------------------------

  late final TourTrigger _tourTrigger = TourTrigger(
    canTry: _canTryTour,
    start: _startTour,
  );

  InboxTourDemo? get _demo => tour?.demo;

  bool _canTryTour() {
    if (tour == null || isClosed) return false;
    final state = viewState.value;
    return (state == AppViewState.content || state == AppViewState.empty) &&
        shell.tab.value == HomeTab.inbox &&
        !isApprovalsOpen &&
        !isSearchOpen.value &&
        !isFocused &&
        unsavedPrompt.value == null;
  }

  /// Real data first: sample cards only without a record of the person's
  /// own, sample requests only without one.
  bool get _hasRealRecords => rows.isNotEmpty;
  bool get _hasRealApprovals => approvals.hasListed;

  /// Should the Records tab draw the tour's sample cards now? Reactive, and
  /// false the moment a real record is there.
  bool get isTourRecordsSample =>
      (_demo?.isRecordsSample.value ?? false) && rows.isEmpty && !isFocused;

  /// Should the Approvals tab draw the tour's sample requests now?
  bool get isTourApprovalsSample =>
      (_demo?.isApprovalsSample.value ?? false) && !approvals.hasListed;

  Future<TourStart> _startTour() async {
    final tour = this.tour;
    if (tour == null || isClosed) return TourStart.failed;
    await WidgetsBinding.instance.endOfFrame;
    if (isClosed) return TourStart.failed;
    return tour.start(
      _tourPorts,
      isSample: !_hasRealRecords || !_hasRealApprovals,
      pendingApprovals: approvals.count,
    );
  }

  late final InboxTourPorts _tourPorts = InboxTourPorts(
    seed: _seedTour,
    restore: _restoreTour,
    expandFirst: () => _tourExpand(true),
    collapseFirst: () => _tourExpand(false),
    openFilter: () => _demo?.isFilterOpen.value = true,
    closeFilter: () => _demo?.isFilterOpen.value = false,
    showApprovals: () => selectTab(InboxTabs.indexOf(InboxTab.approvals)),
    showRecords: () => selectTab(InboxTabs.indexOf(InboxTab.records)),
  );

  bool _seedTour() {
    final d = _demo;
    if (d == null) return false;
    final isRecords = !_hasRealRecords;
    final isApprovals = !_hasRealApprovals;
    d.begin(
      isRecords: isRecords,
      isApprovals: isApprovals,
      now: DateTime.now().millisecondsSinceEpoch,
    );
    return isRecords || isApprovals;
  }

  /// Back on Records with every sample, popup and open card gone. Runs on
  /// every way a tour ends, and more than once.
  void _restoreTour() {
    _tourExpand(false);
    if (isApprovalsOpen) selectTab(InboxTabs.indexOf(InboxTab.records));
    _demo?.end();
  }

  String? _tourExpandedKey;

  /// The first card on screen (a real record, else the sample) opens or
  /// closes. A real card that was already open stays as it was.
  void _tourExpand(bool isOpen) {
    final d = _demo;
    if (d == null) return;
    if (!isOpen) {
      final key = _tourExpandedKey;
      _tourExpandedKey = null;
      if (key == null) return;
      if (key.startsWith('r-')) {
        d.expanded.remove(key);
      } else if (isCardExpanded(key)) {
        toggleCardExpanded(key);
      }
      return;
    }
    final real = rows.firstOrNull;
    if (real != null) {
      final key = 'r${real.id}';
      if (isCardExpanded(key)) return;
      _tourExpandedKey = key;
      toggleCardExpanded(key);
    } else if (d.rows.isNotEmpty) {
      final key = 'r${d.rows.first.id}';
      _tourExpandedKey = key;
      d.expanded.add(key);
    }
  }

  /// A filter panel for the popup the tour shows: nothing is read for it
  /// (no people, no field kinds, no counts) and nothing it does is kept.
  InboxFilterController newSampleFilterPanel() => InboxFilterController(
    inbox: inbox,
    initial: InboxFilter.none,
    baseWhere: InboxScope.me.name,
    isTeamShown: false,
    fieldKinds: null,
    forms: const {},
    approvals: null,
    isSample: true,
    onApply: (_) {},
    onClear: () {},
  )..onInit();

  @override
  void onClose() {
    _tourTrigger.dispose();
    tour?.cancel();
    _ask++;
    live.dispose();
    for (final s in _liveSubs) {
      s.cancel();
    }
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
