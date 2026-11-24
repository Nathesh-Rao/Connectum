import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../core/log/safe.dart';
import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/record_live.dart';
import '../../data/records/record_commands.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/session_store.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import '../home_shell/home_shell_controller.dart';
import '../home_shell/home_tab.dart';
import '../tickets/ticket_detail_controller.dart';
import 'models/inbox_page.dart';
import 'models/inbox_query.dart';
import 'models/inbox_row.dart';

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
  });

  static const title = 'Inbox';
  static const searchHint = 'Search records';
  static const searchNote = 'Searching loaded records';
  static const emptyTitle = 'No records yet.';
  static const noMatchTitle = 'No records match your search.';
  static const errorText =
      'The records could not be read. Use Refresh to try again.';
  static const pageSize = 50;
  static const _moreAt = 600.0;
  static const _staleAfter = Duration(seconds: 30);

  final InboxRepository inbox;
  final TicketRepository tickets;
  final SessionStore store;
  final ConnectivityService connectivity;
  final HomeShellController shell;
  final TicketDetailController Function(int id) newTicketDetail;

  final searchField = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();

  final scope = InboxScope.me.obs;
  final query = ''.obs;
  final isSearchFocused = false.obs;

  /// What the screen shows as a whole. The list itself is [rows].
  final viewState = AppViewState.loading.obs;

  /// The records read so far for [scope] (the page the repository holds).
  final page = Rxn<InboxPage>();

  /// A read of this scope failed and [page] is what was read before.
  final hasError = false.obs;
  final isRefreshing = false.obs;
  final isLoadingMore = false.obs;
  final counts = Rxn<InboxCounts>();

  final _workers = <Worker>[];
  final _details = <int, TicketDetailController>{};
  int _ask = 0;
  bool _isEntered = false;
  DateTime? _readAt;

  @override
  void onInit() {
    super.onInit();
    _workers.addAll([
      ever(query, (_) => _update()),
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
  List<InboxRow> get rows => _matching(page.value?.rows ?? const []);

  bool get hasMore => page.value?.hasMore ?? false;

  // ---- entering and leaving ----------------------------------------------------

  void _enter() {
    if (!_isEntered) {
      _isEntered = true;
      fireAndLog('inbox_controller', () => load());
      return;
    }
    final at = _readAt;
    if (at == null || DateTime.now().difference(at) > _staleAfter) {
      fireAndLog('inbox_controller', () => load(isSilent: true));
    }
  }

  void _onSession() {
    _ask++;
    page.value = null;
    counts.value = null;
    hasError.value = false;
    isLoadingMore.value = false;
    _readAt = null;
    _closeDetails();
    scope.value = InboxScope.me;
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

  InboxQuery _queryFor(InboxScope s) => InboxQuery(scope: [s.name]);

  /// Pull to refresh and the Refresh button. Offline there is nothing to
  /// read: the bar says so and the list stays.
  Future<void> refreshList() async {
    if (!isOnline) {
      if (page.value == null) viewState.value = AppViewState.offline;
      return;
    }
    await load(isSilent: true);
  }

  Future<void> retry() => load();

  void _learnPeople(List<InboxRow> rows) {
    fireAndLog(
      'inbox_controller',
      () => inbox.loadCards([for (final r in rows) r.who]),
    );
  }

  // ---- scope and search ---------------------------------------------------------

  void selectScope(InboxScope next) {
    if (next == scope.value) return;
    if (next == InboxScope.team && !isTeamShown) return;
    scope.value = next;
    _ask++;
    page.value = null;
    hasError.value = false;
    isLoadingMore.value = false;
    if (scroll.hasClients) scroll.jumpTo(0);
    _update();
    fireAndLog('inbox_controller', () => load());
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
    searchField.dispose();
    searchFocus.dispose();
    scroll.dispose();
    super.onClose();
  }
}
