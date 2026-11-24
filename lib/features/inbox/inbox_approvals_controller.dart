import 'dart:async';

import 'package:get/get.dart';

import '../../core/log/safe.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/approval.dart';
import '../../data/repositories/approval_repository.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/socket/call_problem.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'models/approval_pane.dart';
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
    DateTime Function()? now,
    this.afterAnswer = const Duration(milliseconds: 260),
  }) : _now = now ?? DateTime.now;

  static const noteMax = ApprovalRules.maxText;

  final ApprovalRepository approvals;
  final InboxRepository inbox;
  final ConnectivityService connectivity;
  final DateTime Function() _now;

  /// How long an answered card slides out before the list is read again.
  final Duration afterAnswer;

  final filter = ApprovalFilter.all.obs;

  /// The Inbox search text, as typed.
  final query = ''.obs;

  /// Answered cards that are still sliding out of the list.
  final leaving = <int>{}.obs;

  /// Requests with an answer in flight: no second one starts.
  final busy = <int>{}.obs;

  final _timers = <Timer>[];
  Worker? _learnWorker;

  @override
  void onInit() {
    super.onInit();
    _learnWorker = ever(approvals.all, (_) => _learnPeople());
  }

  @override
  void onClose() {
    _learnWorker?.dispose();
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

  /// Rows that match the search, in every state (what the counts count).
  List<Approval> get _searched =>
      ApprovalPane.rows(approvals.all, query: query.value, nameOf: _nameOf);

  Map<ApprovalFilter, int> get counts => ApprovalPane.countsOf(_searched);

  List<ApprovalFilter> get offered => ApprovalPane.offered(counts);

  /// The chosen filter, or All when it has no rows any more.
  ApprovalFilter get activeFilter {
    final f = filter.value;
    return offered.contains(f) ? f : ApprovalFilter.all;
  }

  /// The cards: the filter's rows, newest first, and the ones just answered
  /// that are still sliding out.
  List<Approval> get rows {
    inbox.cardRevision.value;
    final f = activeFilter;
    final q = query.value;
    return [
      for (final a in ApprovalReducer.sorted(approvals.all))
        if (leaving.contains(a.id) ||
            (ApprovalPane.isListed(a) &&
                ApprovalPane.inFilter(a, f) &&
                ApprovalPane.matches(a, q, personName: _nameOf(a))))
          a,
    ];
  }

  /// This card has been answered and no longer belongs to the list.
  bool isLeaving(Approval a) =>
      leaving.contains(a.id) &&
      !(ApprovalPane.isListed(a) &&
          ApprovalPane.inFilter(a, activeFilter) &&
          ApprovalPane.matches(a, query.value, personName: _nameOf(a)));

  AppViewState get viewState {
    if (!approvals.hasRead.value) {
      if (!approvals.hasError.value) return AppViewState.loading;
      return approvals.isOfflineError.value || !isOnline
          ? AppViewState.offline
          : AppViewState.error;
    }
    if (ApprovalPane.listed(approvals.all).isEmpty) return AppViewState.empty;
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
    filter.value = ApprovalFilter.all;
    leaving.clear();
    busy.clear();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void select(ApprovalFilter next) => filter.value = next;

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
      for (final a in approvals.all)
        if (a.from.isNotEmpty) a.from,
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
