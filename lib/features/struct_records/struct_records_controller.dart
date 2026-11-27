import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/widgets/app_notices.dart';
import '../../core/widgets/app_state_view.dart';
import '../../data/models/struct_records.dart';
import '../../data/repositories/struct_records_repository.dart';
import '../../data/smart_view/models/sv_row.dart';
import '../../data/socket/socket_service.dart';
import '../forms/models/form_launch.dart';
import 'models/struct_records_launch.dart';
import '../../core/log/safe.dart';

/// The records screen of `#tstruct <name>`. Records live in memory only. Never
/// an offline-capable screen: with no connection it says so and offers Retry.
class StructRecordsController extends GetxController {
  StructRecordsController({
    required this.repository,
    required this.launch,
    Future<Object?> Function(String route, Object? arguments)? openRoute,
    this.editRefreshDelay = const Duration(milliseconds: 1500),
  }) : _openRoute = openRoute ?? _toNamed;

  final StructRecordsRepository repository;
  final StructRecordsLaunch launch;
  final Duration editRefreshDelay;
  final Future<Object?> Function(String route, Object? arguments) _openRoute;

  static Future<Object?> _toNamed(String route, Object? arguments) async =>
      await Get.toNamed(route, arguments: arguments);

  final scroll = ScrollController();
  final viewState = AppViewState.loading.obs;
  final rows = <SvRow>[].obs;
  final total = 0.obs;
  final isLoadingMore = false.obs;
  final hasMore = false.obs;
  final errorText = ''.obs;
  final deletingIds = <int>{}.obs;
  late final title = launch.caption.obs;

  /// False for a structure Connectum keeps (no New record, Edit or Delete).
  final canAdd = true.obs;

  StructRecordsSchema? _view;
  int _offset = 0;
  int _epoch = 0;
  bool _isReading = false;

  StructRecordsSchema? get view => _view;

  @override
  void onInit() {
    super.onInit();
    scroll.addListener(_onScroll);
    fireAndLog('struct_records_controller', () => load());
  }

  void _onScroll() {
    if (!scroll.hasClients) return;
    final p = scroll.position;
    if (p.maxScrollExtent - p.pixels < 300)
      fireAndLog('struct_records_controller', () => loadMore());
  }

  /// The first page (the whole list is read again).
  Future<void> load({bool isQuiet = false}) async {
    if (_isReading) return;
    _isReading = true;
    final epoch = ++_epoch;
    if (!isQuiet || rows.isEmpty) viewState.value = AppViewState.loading;
    try {
      final v = _view ??= await repository.open(launch.name, launch.scope);
      if (epoch != _epoch) return;
      if (v == null) {
        errorText.value = "Couldn't open that structure. Try again.";
        viewState.value = AppViewState.error;
        return;
      }
      title.value = v.caption;
      canAdd.value = !v.isReadOnly;
      final page = await repository.page(v);
      if (epoch != _epoch) return;
      rows.assignAll(page.rows);
      _offset = page.received;
      total.value = page.total;
      hasMore.value = page.hasMore && page.received > 0;
      viewState.value = rows.isEmpty
          ? AppViewState.empty
          : AppViewState.content;
    } on SocketCallError catch (e) {
      if (epoch != _epoch) return;
      _fail(e);
    } finally {
      _isReading = false;
    }
  }

  void _fail(SocketCallError e) {
    if (rows.isNotEmpty) {
      AppNotices.warning(
        e.isConnectionGap
            ? 'Needs a connection'
            : "Couldn't refresh. Try again.",
      );
      viewState.value = AppViewState.content;
      return;
    }
    if (e.isConnectionGap) {
      viewState.value = AppViewState.offline;
      return;
    }
    errorText.value = e.code == 'not_found' && e.message.isNotEmpty
        ? e.message
        : e.code == 'rate_limited'
        ? 'Too many requests. Try again in a moment.'
        : "Couldn't load the records.";
    viewState.value = AppViewState.error;
  }

  Future<void> refreshList() => load(isQuiet: true);

  Future<void> retry() => load();

  Future<void> loadMore() async {
    final v = _view;
    if (v == null ||
        !hasMore.value ||
        isLoadingMore.value ||
        _isReading ||
        viewState.value != AppViewState.content) {
      return;
    }
    isLoadingMore.value = true;
    final epoch = _epoch;
    try {
      final page = await repository.page(v, offset: _offset);
      if (epoch != _epoch) return;
      final have = {for (final r in rows) r.id};
      rows.addAll([
        for (final r in page.rows)
          if (have.add(r.id)) r,
      ]);
      _offset += page.received;
      total.value = page.total;
      hasMore.value = page.hasMore && page.received > 0;
    } on SocketCallError catch (e) {
      AppNotices.warning(
        e.isConnectionGap
            ? 'Needs a connection'
            : e.code == 'rate_limited'
            ? 'Too many requests. Try again in a moment.'
            : "Couldn't load more. Try again.",
      );
    } finally {
      isLoadingMore.value = false;
    }
  }

  bool canChange(SvRow row) {
    final v = _view;
    return v != null && repository.canChange(v, row);
  }

  /// New record: the add form of `#tstruct-add <name>`, same route and
  /// arguments, then the list is read again when something was saved.
  Future<void> addRecord() async {
    final result = await _openRoute(
      AppRoutes.form,
      FormLaunch(
        name: launch.name,
        scope: launch.scope,
        caption: launch.caption,
        convId: launch.convId,
      ),
    );
    if (result == true)
      fireAndLog('struct_records_controller', () => load(isQuiet: true));
  }

  /// Edit: the app's edit form of a saved record (`submissions.update`),
  /// then the list is read again once the save has had time to reach the
  /// server.
  Future<void> editRecord(SvRow row) async {
    final v = _view;
    if (v == null || !canChange(row)) return;
    final result = await _openRoute(
      AppRoutes.form,
      FormLaunch(
        name: launch.name,
        scope: launch.scope,
        caption: launch.caption,
        mode: FormMode.edit,
        submissionId: '${row.id}',
        savedValues: Map<String, dynamic>.of(row.values),
      ),
    );
    if (result != true) return;
    await Future<void>.delayed(editRefreshDelay);
    await load(isQuiet: true);
  }

  /// Delete (the view has asked already): the server decides. The row goes
  /// only when the server said yes.
  Future<void> deleteRecord(SvRow row) async {
    if (!canChange(row) || deletingIds.contains(row.id)) return;
    deletingIds.add(row.id);
    try {
      final message = await repository.deleteRecord('${row.id}');
      final isGone = message == null || message.contains('no longer exists');
      if (isGone) {
        rows.removeWhere((r) => r.id == row.id);
        if (total.value > 0) total.value--;
        _offset = _offset > 0 ? _offset - 1 : 0;
        if (rows.isEmpty && !hasMore.value) {
          viewState.value = AppViewState.empty;
        }
      }
      if (message == null) {
        AppNotices.success('Record #${row.id} was removed.');
      } else {
        AppNotices.warning(message);
      }
    } finally {
      deletingIds.remove(row.id);
    }
  }

  @override
  void onClose() {
    scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.onClose();
  }
}
