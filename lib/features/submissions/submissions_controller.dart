import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/form_card.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../home_shell/home_shell_controller.dart';
import 'models/submission_row.dart';

class FormFilter {
  const FormFilter(this.name, this.label, this.count);

  final String name;
  final String label;
  final int count;
}

/// My Submissions: the cached list (mine only), newest first. It is never an
/// offline screen: the cache shows whatever the connection, and the offline
/// bar says so. The list is refreshed when the tab opens, on pull-to-refresh
/// and after a reconnect (the repository does that one).
class SubmissionsController extends GetxController {
  SubmissionsController({
    required this.submissions,
    required this.connectivity,
    required this.shell,
  });

  static const _tabIndex = 2;
  static const _syncEvery = Duration(seconds: 20);

  final SubmissionRepository submissions;
  final ConnectivityService connectivity;
  final HomeShellController shell;

  final searchField = TextEditingController();
  final searchFocus = FocusNode();

  final query = ''.obs;
  final viewState = AppViewState.loading.obs;
  final rows = <SubmissionRow>[].obs;

  /// The forms that really exist in the data, and the statuses (only when the
  /// data has any). Selected: index into the list, 0 is "All".
  final forms = <FormFilter>[].obs;
  final statuses = <String>[].obs;
  final selectedForm = 0.obs;
  final selectedStatus = 0.obs;

  final _all = <SubmissionRow>[];
  final _workers = <Worker>[];
  bool _isSyncing = false;
  bool _hasSyncFailed = false;
  bool _hasSyncedOnce = false;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onInit() {
    super.onInit();
    _workers.addAll([
      ever(submissions.submissions, (_) => _build()),
      ever(submissions.definitions, (_) => _build()),
      ever(submissions.isLoaded, (_) => _build()),
      ever(query, (_) => _filter()),
      ever(selectedForm, (_) => _filter()),
      ever(selectedStatus, (_) => _filter()),
      ever(shell.index, (i) {
        if (i == _tabIndex) unawaited(_syncIfStale());
      }),
    ]);
    _build();
    unawaited(_sync());
  }

  bool get isOnline => connectivity.state.value == AppConnectivity.online;

  Future<void> _syncIfStale() async {
    if (DateTime.now().difference(_lastSync) < _syncEvery) return;
    await _sync();
  }

  Future<void> _sync() async {
    if (_isSyncing || !isOnline) return;
    _isSyncing = true;
    _lastSync = DateTime.now();
    _updateState();
    final isOk = await submissions.syncFromServer();
    _isSyncing = false;
    _hasSyncFailed = !isOk;
    if (isOk) _hasSyncedOnce = true;
    _updateState();
  }

  /// Pull-to-refresh. Offline there is nothing to fetch: the bar already says
  /// so, and the cached list stays.
  Future<void> refreshList() async {
    if (!isOnline) return;
    _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
    await _sync();
  }

  Future<void> retry() async {
    _hasSyncFailed = false;
    await submissions.reload();
    await _sync();
  }

  void _build() {
    _all
      ..clear()
      ..addAll(
        submissions.submissions.map(
          (s) => SubmissionRow(
            FormCardData.fromSubmission(
              s,
              definition: submissions.definitions[s.tstruct],
            ),
          ),
        ),
      );
    final counts = <String, int>{};
    final labels = <String, String>{};
    for (final r in _all) {
      counts[r.card.structure] = (counts[r.card.structure] ?? 0) + 1;
      labels[r.card.structure] = r.card.caption;
    }
    final names = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final previousForm = selectedForm.value > 0 &&
            selectedForm.value <= forms.length
        ? forms[selectedForm.value - 1].name
        : null;
    forms.assignAll([
      for (final n in names) FormFilter(n, labels[n] ?? n, counts[n]!),
    ]);
    final previousStatus = selectedStatus.value > 0 &&
            selectedStatus.value <= statuses.length
        ? statuses[selectedStatus.value - 1]
        : null;
    statuses.assignAll({
      for (final r in _all)
        if (r.card.status != null) r.card.status!,
    });
    selectedForm.value = previousForm == null
        ? 0
        : names.indexOf(previousForm) + 1;
    selectedStatus.value = previousStatus == null
        ? 0
        : statuses.indexOf(previousStatus) + 1;
    _filter();
  }

  void _filter() {
    final q = query.value.trim().toLowerCase();
    final form = selectedForm.value > 0 && selectedForm.value <= forms.length
        ? forms[selectedForm.value - 1].name
        : null;
    final status =
        selectedStatus.value > 0 && selectedStatus.value <= statuses.length
        ? statuses[selectedStatus.value - 1]
        : null;
    rows.assignAll([
      for (final r in _all)
        if ((form == null || r.card.structure == form) &&
            (status == null || r.card.status == status) &&
            (q.isEmpty || r.searchText.contains(q)))
          r,
    ]);
    _updateState();
  }

  void _updateState() {
    if (!submissions.isLoaded.value) {
      viewState.value = AppViewState.loading;
    } else if (_all.isEmpty) {
      viewState.value = _isSyncing && !_hasSyncedOnce
          ? AppViewState.loading
          : _hasSyncFailed
          ? AppViewState.error
          : AppViewState.empty;
    } else {
      viewState.value = rows.isEmpty
          ? AppViewState.noResults
          : AppViewState.content;
    }
  }

  void onQueryChanged(String value) => query.value = value;

  void clearSearch() {
    searchField.clear();
    query.value = '';
  }

  void open(FormCardData d) =>
      Get.toNamed(AppRoutes.submissionDetailOf(d.id));

  @override
  void onClose() {
    for (final w in _workers) {
      w.dispose();
    }
    searchField.dispose();
    searchFocus.dispose();
    super.onClose();
  }
}
