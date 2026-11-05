import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/widgets/app_notice_card.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/approval.dart';
import '../../data/repositories/approval_repository.dart';
import '../../data/socket/call_problem.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';
import 'approvals_texts.dart';
import 'models/approval_reducer.dart';
import 'models/approval_rules.dart';

/// The Approvals screen: "To review" and "Sent by me", a history filter, and
/// the answers. An answer is sent once and never replayed: a failure is shown
/// with the server's own words and a manual Retry where that is safe.
class ApprovalsController extends GetxController
    with GetSingleTickerProviderStateMixin {
  ApprovalsController({required this.approvals, required this.connectivity});

  final ApprovalRepository approvals;
  final ConnectivityService connectivity;

  static const filters = ['pending', 'accepted', 'rejected', 'ignored'];
  static const filterLabels = [
    ApprovalsTexts.filterPending,
    ApprovalsTexts.filterAccepted,
    ApprovalsTexts.filterRejected,
    ApprovalsTexts.filterIgnored,
  ];

  late final tabController = TabController(length: 2, vsync: this);
  final selectedFilter = 0.obs;

  /// The requests of the selected status, for both tabs; each tab shows its
  /// own direction of them.
  final items = <Approval>[].obs;
  final viewState = AppViewState.loading.obs;
  final hasMore = false.obs;
  final isLoadingMore = false.obs;

  /// An answer is in flight: no second one starts.
  final isBusy = false.obs;

  final _kept = <int>{};
  StreamSubscription<ApprovalChange>? _changes;
  StreamSubscription<void>? _refreshes;
  int _loaded = 0;
  int _seq = 0;

  String get status => filters[selectedFilter.value];
  bool get isPendingFilter => selectedFilter.value == 0;

  /// Cards for tab [index]: 0 to review, 1 sent by me.
  List<Approval> tab(int index) => [
    for (final r in items)
      if (index == 0 ? ApprovalReducer.inReview(r) : ApprovalReducer.inSent(r))
        r,
  ];

  Approval? find(int id) {
    for (final r in items) {
      if (r.id == id) return r;
    }
    return null;
  }

  int get reviewCount => tab(0).length;

  @override
  void onInit() {
    super.onInit();
    _changes = approvals.changes.listen(_onChange);
    _refreshes = approvals.refreshes.listen((_) => unawaited(load()));
    unawaited(load(isQuiet: false));
  }

  @override
  void onClose() {
    _changes?.cancel();
    _refreshes?.cancel();
    tabController.dispose();
    super.onClose();
  }

  // ---- reading ---------------------------------------------------------------

  Future<void> load({bool isQuiet = true}) async {
    final seq = ++_seq;
    if (items.isEmpty && viewState.value != AppViewState.content) {
      viewState.value = AppViewState.loading;
    }
    try {
      final page = await approvals.list(status: status);
      if (seq != _seq) return;
      items.assignAll(
        ApprovalReducer.refreshed(page.requests, items.toList(), _kept),
      );
      _loaded = page.requests.length;
      hasMore.value = page.hasMore;
      _settle();
    } on SocketCallError catch (e) {
      if (seq != _seq) return;
      if (items.isNotEmpty) {
        viewState.value = AppViewState.content;
        if (!isQuiet) _tell(CallProblem.of(e), retry: load);
      } else {
        viewState.value = connectivity.state.value == AppConnectivity.online
            ? AppViewState.error
            : AppViewState.offline;
      }
    }
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !hasMore.value) return;
    isLoadingMore.value = true;
    try {
      final page = await approvals.list(status: status, offset: _loaded);
      items.assignAll(ApprovalReducer.appended(items, page.requests));
      _loaded += page.requests.length;
      hasMore.value = page.hasMore;
    } on SocketCallError catch (e) {
      _tell(CallProblem.of(e), retry: loadMore);
    } finally {
      isLoadingMore.value = false;
    }
  }

  void selectFilter(int index) {
    if (index == selectedFilter.value) return;
    selectedFilter.value = index;
    _kept.clear();
    items.clear();
    hasMore.value = false;
    _loaded = 0;
    _seq++;
    viewState.value = AppViewState.loading;
    unawaited(load(isQuiet: false));
  }

  void _settle() {
    viewState.value = items.isEmpty ? AppViewState.empty : AppViewState.content;
  }

  // ---- events ----------------------------------------------------------------

  void _onChange(ApprovalChange change) {
    if (change.isCreated) {
      items.assignAll(
        ApprovalReducer.applyCreated(
          items.toList(),
          change.request,
          status: status,
        ),
      );
      AppNotices.info(ApprovalsTexts.newRequestNotice);
    } else {
      items.assignAll(
        ApprovalReducer.applyResolved(items.toList(), change.request),
      );
    }
    _settle();
  }

  // ---- answering -------------------------------------------------------------

  /// Sends the answer. True when the server took it. The card changes in
  /// place to its new status; it is not removed.
  Future<bool> respond(
    Approval r,
    ApprovalAction action, {
    String? reason,
    String? comment,
    bool? allowResubmit,
  }) async {
    if (isBusy.value) return false;
    if (!ApprovalRules.canSend(action, reason ?? '')) return false;
    isBusy.value = true;
    try {
      final answered = await approvals.respond(
        r.id,
        action.wire,
        reason: reason,
        comment: comment,
        allowResubmit: allowResubmit,
      );
      _kept.add(r.id);
      items.assignAll(ApprovalReducer.applyResolved(items.toList(), answered));
      return true;
    } on SocketCallError catch (e) {
      final problem = CallProblem.of(e, isWrite: true);
      _tell(
        problem,
        retry: () => respond(
          r,
          action,
          reason: reason,
          comment: comment,
          allowResubmit: allowResubmit,
        ),
      );
      if (problem.kind == CallProblemKind.notFound) {
        items.assignAll(ApprovalReducer.remove(items.toList(), r.id));
        _settle();
      } else if (problem.shouldRefresh) {
        unawaited(load());
      }
      return false;
    } finally {
      isBusy.value = false;
    }
  }

  void _tell(CallProblem problem, {required Future<void> Function() retry}) {
    AppNotices.show(
      problem.text,
      variant:
          problem.canRetry || problem.kind == CallProblemKind.unknownOutcome
          ? AppNoticeVariant.warning
          : AppNoticeVariant.error,
      actionLabel: problem.canRetry ? ApprovalsTexts.retry : null,
      onAction: problem.canRetry ? () => unawaited(retry()) : null,
    );
  }
}
