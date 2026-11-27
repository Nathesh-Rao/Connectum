import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/features/settings/settings.dart';
import 'log_viewer_prefs.dart';
import 'models/log_document.dart';

/// State of the in-app log viewer: reads the file off the UI thread, keeps
/// the scroll, the wrap and size choices and the search.
class LogViewerController extends GetxController {
  LogViewerController({
    required this.sink,
    required this.logs,
    this.reader = const LogTextReader(),
    LogViewerPrefs? prefs,
    this.searchDelay = const Duration(milliseconds: 250),
  }) : _prefs = prefs;

  final LogFileSink sink;
  final LogsController logs;
  final LogTextReader reader;
  final Duration searchDelay;

  final scroll = ScrollController();
  final searchField = TextEditingController();
  final searchFocus = FocusNode();

  final viewState = AppViewState.loading.obs;
  final doc = LogDocument.empty.obs;
  final fileName = ''.obs;
  final errorText = ''.obs;
  final isWrap = true.obs;
  final size = LogTextSize.medium.obs;
  final isSearching = false.obs;
  final hits = LogSearchResult.empty.obs;
  final current = 0.obs;
  final isFinding = false.obs;

  /// Set by the view: how lines map to rows, and the height of a row.
  LogRowIndex? rows;
  double lineExtent = 18;

  Map<int, List<int>> hitStarts = const {};
  int queryLength = 0;

  LogViewerPrefs? _prefs;
  bool _isFirst = true;
  bool _isLoading = false;
  int _searchToken = 0;
  Timer? _timer;

  LogHit? get currentHit => hits.value.hits.isEmpty
      ? null
      : hits.value.hits[current.value.clamp(0, hits.value.hits.length - 1)];

  bool get isAtBottom => !scroll.hasClients || scroll.position.extentAfter < 24;

  @override
  void onReady() {
    super.onReady();
    load();
  }

  @override
  void onClose() {
    _timer?.cancel();
    scroll.dispose();
    searchField.dispose();
    searchFocus.dispose();
    logs.dispose();
    super.onClose();
  }

  Future<void> load({bool isRefresh = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    final wasAtBottom = isAtBottom;
    if (!isRefresh || viewState.value == AppViewState.error) {
      viewState.value = AppViewState.loading;
    }
    try {
      final File? file = await sink.fileForExport();
      if (file == null) {
        AppLog.w('log_viewer', 'open: no log file on disk');
        doc.value = LogDocument.empty;
        viewState.value = AppViewState.empty;
        return;
      }
      fileName.value = file.uri.pathSegments.last;
      if (_prefs == null) {
        _prefs = LogViewerPrefs(file.parent);
        size.value = await _prefs!.loadSize();
      }
      final read = await reader.read(file);
      doc.value = read;
      AppLog.i(
        'log_viewer',
        'open: ${file.path} ${read.lines.length} lines${read.isPartial ? ' (last part)' : ''}',
      );
      errorText.value = '';
      viewState.value = read.isEmpty
          ? AppViewState.empty
          : AppViewState.content;
      if (searchField.text.isNotEmpty) await _find(searchField.text);
      if (_isFirst || wasAtBottom) jumpToLatest();
      _isFirst = false;
    } on Object catch (e, st) {
      AppLog.e('log_viewer', e, st, 'read $e');
      errorText.value = '$e';
      viewState.value = AppViewState.error;
    } finally {
      _isLoading = false;
    }
  }

  void jumpToLatest() => _jump((p) => p.maxScrollExtent);

  void jumpToTop() => _jump((_) => 0);

  /// Rows are all one height, so the target is exact once the list has been
  /// laid out; the jump waits for that frame.
  void _jump(double Function(ScrollPosition) target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      final p = scroll.position;
      p.jumpTo(target(p).clamp(p.minScrollExtent, p.maxScrollExtent));
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void setWrap(bool value) => isWrap.value = value;

  Future<void> setSize(LogTextSize value) async {
    size.value = value;
    await _prefs?.saveSize(value);
  }

  Future<void> saveToDevice() => logs.saveToDevice();

  Future<void> share() => logs.share();

  void toggleSearch() {
    if (isSearching.value) {
      closeSearch();
    } else {
      isSearching.value = true;
      searchFocus.requestFocus();
    }
  }

  void closeSearch() {
    _timer?.cancel();
    _searchToken++;
    isSearching.value = false;
    searchField.clear();
    _setHits(LogSearchResult.empty, 0);
    isFinding.value = false;
  }

  void onQuery(String text) {
    _timer?.cancel();
    if (text.isEmpty) {
      _searchToken++;
      _setHits(LogSearchResult.empty, 0);
      isFinding.value = false;
      return;
    }
    isFinding.value = true;
    _timer = Timer(searchDelay, () => _find(text));
  }

  Future<void> _find(String text) async {
    final token = ++_searchToken;
    try {
      final result = await reader.search(doc.value, text);
      if (token != _searchToken) return;
      _setHits(result, text.length);
      if (result.hits.isNotEmpty) _reveal(result.hits.first);
    } on Object catch (e, st) {
      AppLog.e('log_viewer', e, st, 'search');
    } finally {
      if (token == _searchToken) isFinding.value = false;
    }
  }

  void _setHits(LogSearchResult result, int length) {
    final map = <int, List<int>>{};
    for (final h in result.hits) {
      (map[h.line] ??= []).add(h.start);
    }
    hitStarts = map;
    queryLength = length;
    current.value = 0;
    hits.value = result;
  }

  void nextHit() => _step(1);

  void previousHit() => _step(-1);

  void _step(int by) {
    final n = hits.value.hits.length;
    if (n == 0) return;
    current.value = (current.value + by) % n;
    _reveal(hits.value.hits[current.value]);
  }

  void _reveal(LogHit hit) {
    final r = rows;
    if (!scroll.hasClients || r == null) return;
    final p = scroll.position;
    final at = r.rowOf(hit.line, hit.start) * lineExtent;
    final isShown =
        at >= p.pixels && at + lineExtent <= p.pixels + p.viewportDimension;
    if (isShown) return;
    p.jumpTo(
      (at - p.viewportDimension * 0.3).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      ),
    );
  }
}
