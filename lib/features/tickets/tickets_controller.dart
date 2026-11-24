import 'dart:async';

import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/theme/app_motion.dart';
import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/ticket.dart';
import '../../data/repositories/ticket_repository.dart';
import '../../data/socket/call_problem.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'models/ticket_reducer.dart';
import 'tickets_texts.dart';
import '../../core/log/safe.dart';

/// One tab's list.
class TicketList {
  final items = <Ticket>[].obs;
  final viewState = AppViewState.loading.obs;
  final hasMore = false.obs;
  final isLoadingMore = false.obs;

  /// Rows that are sliding out; they leave [items] when the motion is done.
  final leaving = <int>{}.obs;

  /// Rows read from the server so far (the next page's `offset`).
  int loaded = 0;

  /// The newest read; an older answer arriving later is dropped.
  int seq = 0;
}

/// The Tickets section of the Tasks screen: "With me", "Raised by me" and
/// "Involved", each read with `records.mine` (pages are read until `hasMore`
/// is false; a page can be shorter than the limit), and a filter by form that
/// works on what is already read (the server has none). The list of forms is
/// the distinct structures in the replies. Tickets are a third list: they
/// never mix with the To-do tasks or the approvals.
class TicketsController extends GetxController {
  TicketsController({required this.tickets, required this.connectivity});

  final TicketRepository tickets;
  final ConnectivityService connectivity;

  static const tabs = ['with', 'raised', 'involved'];

  /// A guard on the paging loop: 50 pages of 100.
  static const maxPages = 50;

  /// 0 = with me, 1 = raised by me, 2 = involved.
  final selectedTab = 0.obs;
  final lists = {for (final t in tabs) t: TicketList()};

  /// The form key picked in the filter; null = all forms.
  final selectedForm = RxnString();
  StreamSubscription<void>? _refreshes;

  String get me => tickets.me;
  RxInt get withTotal => tickets.withTotal;

  @override
  void onInit() {
    super.onInit();
    _refreshes = tickets.refreshes.listen((_) => fireAndLog('tickets_controller', () => refreshAll()), onError: streamOnError('tickets_controller'));
    fireAndLog('tickets_controller', () => refreshAll());
  }

  @override
  void onClose() {
    _refreshes?.cancel();
    super.onClose();
  }

  // ---- reading ---------------------------------------------------------------

  bool _isRefreshing = false;
  bool _wantsAgain = false;

  /// Every tab again. One refresh at a time: events that arrive during one
  /// ask for a single further round after it.
  Future<void> refreshAll() async {
    if (_isRefreshing) {
      _wantsAgain = true;
      return;
    }
    _isRefreshing = true;
    try {
      do {
        _wantsAgain = false;
        await Future.wait([for (final as in tabs) load(as)]);
      } while (_wantsAgain);
    } finally {
      _isRefreshing = false;
    }
  }

  /// A tab, replacing what is shown: the first page, then every next page
  /// while the server says `hasMore`. [isQuiet]: a refresh behind the screen
  /// never turns a list into an error. An empty list shows the first page as
  /// soon as it is read; a list that already has rows is replaced once, when
  /// every page is in, so rows do not jump.
  Future<void> load(String as, {bool isQuiet = true}) async {
    final list = lists[as]!;
    final seq = ++list.seq;
    if (list.items.isEmpty && list.viewState.value != AppViewState.content) {
      list.viewState.value = AppViewState.loading;
    }
    final isFirstRead = list.items.isEmpty;
    final read = <Ticket>[];
    var count = 0;
    var hasMore = false;
    try {
      for (var pages = 0; pages < maxPages; pages++) {
        final page = await tickets.mine(as: as, offset: count);
        if (seq != list.seq) return;
        count = page.nextOffset(as, count);
        read.addAll(
          TicketReducer.appended(read, page.tickets).skip(read.length),
        );
        hasMore = page.hasMore && page.tickets.isNotEmpty;
        if (isFirstRead && pages == 0) {
          _show(list, read);
          list.viewState.value = list.items.isEmpty
              ? AppViewState.empty
              : AppViewState.content;
        }
        if (!hasMore) break;
        if (isFirstRead) list.items.assignAll(read);
      }
      _show(list, read);
      list.loaded = count;
      list.hasMore.value = hasMore;
      list.viewState.value = list.items.isEmpty
          ? AppViewState.empty
          : AppViewState.content;
    } on SocketCallError catch (e) {
      if (seq != list.seq) return;
      if (read.isNotEmpty && isFirstRead) {
        list.loaded = count;
        list.hasMore.value = true;
        list.viewState.value = AppViewState.content;
        if (!isQuiet) _tell(CallProblem.of(e), retry: () => loadMore(as));
      } else if (list.items.isNotEmpty) {
        list.viewState.value = AppViewState.content;
        if (!isQuiet) _tell(CallProblem.of(e), retry: () => load(as));
      } else {
        list.viewState.value =
            connectivity.state.value == AppConnectivity.online
            ? AppViewState.error
            : AppViewState.offline;
      }
    }
  }

  /// Puts [fresh] on screen. Rows that were shown and are no longer listed
  /// (sent on, completed, dropped) stay a moment in place and slide out.
  void _show(TicketList list, List<Ticket> fresh) {
    final shown = list.items.toList();
    final diff = TicketReducer.refreshed(fresh, shown);
    if (diff.gone.isEmpty || shown.isEmpty) {
      list.items.assignAll(diff.next);
      return;
    }
    final merged = [...diff.next];
    for (final t in diff.gone) {
      final at = shown.indexWhere((s) => s.id == t.id).clamp(0, merged.length);
      merged.insert(at, t);
    }
    list.items.assignAll(merged);
    final ids = {for (final t in diff.gone) t.id};
    list.leaving.addAll(ids);
    Future<void>.delayed(AppDurations.slow, () {
      list.items.assignAll([
        for (final t in list.items)
          if (!ids.contains(t.id)) t,
      ]);
      list.leaving.removeAll(ids);
      if (list.items.isEmpty && list.viewState.value == AppViewState.content) {
        list.viewState.value = AppViewState.empty;
      }
    });
  }

  /// "Show more": only when a page failed half way; the next rows after the
  /// ones already held.
  Future<void> loadMore(String as) async {
    final list = lists[as]!;
    if (list.isLoadingMore.value || !list.hasMore.value) return;
    list.isLoadingMore.value = true;
    try {
      final page = await tickets.mine(as: as, offset: list.loaded);
      list.items.assignAll(TicketReducer.appended(list.items, page.tickets));
      list.loaded = page.nextOffset(as, list.loaded);
      list.hasMore.value = page.hasMore;
    } on SocketCallError catch (e) {
      _tell(CallProblem.of(e), retry: () => loadMore(as));
    } finally {
      list.isLoadingMore.value = false;
    }
  }

  // ---- filter ----------------------------------------------------------------

  /// The forms present in either list, by caption: the filter's chips.
  List<TicketForm> get forms {
    final byKey = <String, TicketForm>{};
    for (final list in lists.values) {
      for (final t in list.items) {
        final f = t.form;
        if (f != null) byKey[f.key] = f;
      }
    }
    return byKey.values.toList()
      ..sort((a, b) => a.caption.compareTo(b.caption));
  }

  /// 0 = all forms.
  int get selectedIndex {
    final key = selectedForm.value;
    if (key == null) return 0;
    final i = forms.indexWhere((f) => f.key == key);
    return i < 0 ? 0 : i + 1;
  }

  void selectFilter(int index) {
    final all = forms;
    selectedForm.value = index <= 0 || index > all.length
        ? null
        : all[index - 1].key;
  }

  /// The rows of [as] the filter lets through.
  List<Ticket> visible(String as) {
    final key = selectedForm.value;
    final items = lists[as]!.items.toList();
    if (key == null) return items;
    if (!forms.any((f) => f.key == key)) return items;
    return [
      for (final t in items)
        if (t.tstruct == key) t,
    ];
  }

  // ---- opening ---------------------------------------------------------------

  void open(Ticket t) => Get.toNamed(AppRoutes.ticketOf(t.id));

  void _tell(CallProblem problem, {required Future<void> Function() retry}) {
    AppNotices.show(
      problem.text,
      variant: problem.canRetry
          ? AppNoticeVariant.warning
          : AppNoticeVariant.error,
      actionLabel: problem.canRetry ? TicketsTexts.retry : null,
      onAction: problem.canRetry ? () => fireAndLog('tickets_controller', () => retry()) : null,
    );
  }
}
