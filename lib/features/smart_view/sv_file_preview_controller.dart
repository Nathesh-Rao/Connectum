import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/crash/crash_breadcrumbs.dart';
import 'package:connectum/core/log/log.dart';
import 'package:connectum/core/widgets/widgets.dart';
import 'package:connectum/data/repositories/repositories.dart';
import '../../data/attachment_cache.dart';
import '../../data/smart_view/preview/sv_preview_parsers.dart';
import '../../data/smart_view/preview/sv_xlsx_parser.dart';
import '../../data/smart_view/sv_file.dart';

enum SvFilePhase { idle, loading, ready, error }

/// How a Download ended.
enum SvDownload { saved, cancelled, failed, notFetched }

/// What the viewer knows about one file of the record.
class SvFileLoad {
  SvFileLoad(this.file);

  final SvFile file;
  final phase = SvFilePhase.idle.obs;

  /// 0 to 1; stays 0 while the length is unknown.
  final progress = 0.0.obs;

  /// Bytes of a network download so far (never goes backwards); stays empty
  /// for a 304 or a kept copy.
  final transfer = SvFileProgress.none.obs;
  final message = RxnString();
  final problem = Rxn<SvFileProblem>();
  final text = RxnString();
  final isCut = false.obs;

  /// A sheet is being read; the viewer shows a skeleton table meanwhile.
  final isParsing = false.obs;

  /// The server could not be reached: the kept copy is shown unchecked.
  final isMaybeStale = false.obs;

  /// Set by the picture and PDF viewers while zoomed in: the swipe between
  /// files is off then.
  final isZoomed = false.obs;
  SvSheetBook? sheet;
  SvDocText? doc;
  SvZipListing? zip;

  /// The viewer shows the file's own content (a picture or text) only when
  /// this is true; otherwise the file card.
  final isShowable = false.obs;
  File? local;
  CancelToken? cancel;

  /// The file is a picture the first bytes confirmed.
  bool isImage = false;
}

/// The file viewer of one record: the record's files, the page shown, and the
/// fetch, save, open and share of each. Pictures and text load when their page
/// opens; everything else loads when asked, so a big file is never fetched
/// just to be looked at.
class SvFilePreviewController extends GetxController {
  SvFilePreviewController({
    required this.files,
    required this.repo,
    int index = 0,
  }) : index = index.clamp(0, files.length - 1).obs {
    loads = [for (final f in files) SvFileLoad(f)];
    pages = PageController(initialPage: this.index.value);
  }

  final List<SvFile> files;
  final SvFileRepository repo;
  final RxInt index;
  late final List<SvFileLoad> loads;
  late final PageController pages;

  /// The dialog is full screen.
  final isFull = false.obs;

  /// Text viewer: wrap long lines.
  final isWrap = true.obs;

  /// Sheets, Word, slides and zip listings over this are not parsed.
  static const maxParseBytes = 15 * 1024 * 1024;
  static const _inlineParseBytes = 256 * 1024;

  SvFileLoad get current => loads[index.value];

  @override
  void onReady() {
    super.onReady();
    CrashBreadcrumbs.add(Crumb.filePreview, code: current.file.kind.name);
    _autoLoad(index.value);
  }

  @override
  void onClose() {
    for (final l in loads) {
      l.cancel?.cancel();
    }
    pages.dispose();
    super.onClose();
  }

  void onPage(int i) {
    index.value = i;
    _autoLoad(i);
  }

  void _autoLoad(int i) {
    final l = loads[i];
    final viewer = l.file.viewer;
    if (viewer == SvViewer.none || l.phase.value != SvFilePhase.idle) return;
    final isParsed =
        viewer == SvViewer.sheet ||
        viewer == SvViewer.docx ||
        viewer == SvViewer.pptx ||
        viewer == SvViewer.zip;
    final isXlsx = SvFile.extensionOf(l.file.name) == 'xlsx';
    if (isParsed &&
        l.file.size > (isXlsx ? SvXlsxParser.maxFileBytes : maxParseBytes)) {
      return;
    }
    if (l.file.size > SvFileRepository.maxPreviewBytes) {
      l.problem.value = SvFileProblem.tooLarge;
      l.message.value =
          'This file is too large to preview. Download it to see it all.';
      l.phase.value = SvFilePhase.error;
      return;
    }
    ensure(l);
  }

  /// Makes the file local with progress; null when it failed or was
  /// cancelled (the state says which).
  Future<File?> ensure(SvFileLoad l) async {
    if (l.phase.value == SvFilePhase.loading) return null;
    final known = l.local;
    if (known != null && known.existsSync()) return known;
    l.phase.value = SvFilePhase.loading;
    l.progress.value = 0;
    if (l.transfer.value.isStarted) l.transfer.value = SvFileProgress.none;
    l.message.value = null;
    l.problem.value = null;
    final cancel = l.cancel = CancelToken();
    try {
      final got = await repo.fetch(
        l.file,
        onProgress: (p) {
          if (identical(l.cancel, cancel) && p > l.progress.value) {
            l.progress.value = p;
          }
        },
        onTransfer: (t) {
          if (identical(l.cancel, cancel) &&
              t.received > l.transfer.value.received) {
            l.transfer.value = t;
          }
        },
        cancel: cancel,
      );
      final file = got.file;
      l.isMaybeStale.value = got.isMaybeStale;
      l.local = file;
      await _prepare(l, file);
      l.phase.value = SvFilePhase.ready;
      return file;
    } on SvFileException catch (e) {
      if (e.isCancel) {
        l.phase.value = SvFilePhase.idle;
      } else {
        l.problem.value = e.problem;
        l.message.value = e.message;
        l.phase.value = SvFilePhase.error;
      }
      return null;
    }
  }

  Future<void> _prepare(SvFileLoad l, File file) async {
    switch (l.file.viewer) {
      case SvViewer.image:
        l.isImage = await repo.looksLikeImage(file);
        l.isShowable.value = l.isImage;
      case SvViewer.pdf:
        l.isShowable.value = await repo.looksLikePdf(file);
      case SvViewer.video:
      case SvViewer.audio:
        l.isShowable.value = true;
      case SvViewer.text:
        final t = await repo.readText(file);
        final pretty = l.file.name.toLowerCase().endsWith('.json')
            ? SvPreviewParsers.prettyJson(t.text)
            : null;
        l.text.value = t.isCut ? t.text : (pretty ?? t.text);
        l.isCut.value = t.isCut;
        l.isShowable.value = true;
      case SvViewer.sheet:
        await _prepareSheet(l, file);
      case SvViewer.docx:
        final bytes = await file.readAsBytes();
        l.doc = await _parse(SvPreviewParsers.parseDocx, bytes, bytes.length);
        l.isShowable.value = l.doc != null;
      case SvViewer.pptx:
        final bytes = await file.readAsBytes();
        l.doc = await _parse(SvPreviewParsers.parsePptx, bytes, bytes.length);
        l.isShowable.value = l.doc != null;
      case SvViewer.zip:
        final bytes = await file.readAsBytes();
        l.zip = await _parse(SvPreviewParsers.listZip, bytes, bytes.length);
        l.isShowable.value = l.zip != null;
      case SvViewer.none:
        break;
    }
  }

  /// A csv / tsv, or an xlsx read in an isolate. Anything that cannot be read
  /// leaves the file card, never a spinner.
  Future<void> _prepareSheet(SvFileLoad l, File file) async {
    l.isParsing.value = true;
    try {
      final bytes = await file.readAsBytes();
      if (SvFile.extensionOf(l.file.name) == 'xlsx') {
        final book = await compute(SvXlsxParser.parse, bytes);
        l.sheet = book;
        l.isShowable.value = book != null;
        return;
      }
      final table = await _parse(
        SvPreviewParsers.parseCsvBytes,
        bytes,
        bytes.length,
      );
      l.sheet = SvSheetBook([table]);
      l.isShowable.value = table.rows.isNotEmpty;
    } on Object catch (e, st) {
      AppLog.e('sv_file_preview', e, st);
      l.sheet = null;
      l.isShowable.value = false;
    } finally {
      l.isParsing.value = false;
    }
  }

  /// Small inputs parse in place; big ones in an isolate.
  Future<R> _parse<A, R>(R Function(A) fn, A input, int size) =>
      size > _inlineParseBytes ? compute(fn, input) : Future.value(fn(input));

  void toggleFull() => isFull.toggle();

  void cancel() => current.cancel?.cancel();

  Future<void> retry() => ensure(current);

  /// Saves the current file where the person picks, in the system save
  /// dialog. A cancel does nothing; a failure says so with Retry, and after a
  /// second failure offers Share instead.
  Future<SvDownload> download({bool isRetry = false}) async {
    final l = current;
    final local = await ensure(l);
    if (local == null) return SvDownload.notFetched;
    try {
      final name = await repo.saveAs(l.file, local);
      if (name == null) return SvDownload.cancelled;
      AppNotices.show(
        'Saved as {name}',
        values: {'name': name},
        variant: AppNoticeVariant.success,
      );
      return SvDownload.saved;
    } on SvSaveException {
      if (isRetry) {
        AppNotices.show(
          "Still couldn't save it. You can share the file instead.",
          variant: AppNoticeVariant.error,
          actionLabel: 'Share',
          onAction: () =>
              fireAndLog('sv_file_preview_controller', () => share()),
        );
      } else {
        AppNotices.show(
          "The file couldn't be saved. Try again.",
          variant: AppNoticeVariant.error,
          actionLabel: 'Retry',
          onAction: () => fireAndLog(
            'sv_file_preview_controller',
            () => download(isRetry: true),
          ),
        );
      }
      return SvDownload.failed;
    }
  }

  Future<void> openWith() async {
    final local = await ensure(current);
    if (local == null) return;
    final outcome = await repo.open(local);
    if (outcome == OpenOutcome.noApp) {
      AppNotices.warning('No app on this phone can open this file.');
    } else if (outcome == OpenOutcome.failed) {
      AppNotices.error("The file couldn't be opened.");
    }
  }

  Future<void> share() async {
    final local = await ensure(current);
    if (local == null) return;
    await repo.share(local, current.file);
  }

  /// "Share to Connectum" is offered when sharing is set up.
  bool get canShareToConnectum => repo.connectumShare != null;

  /// Makes the current file local first (the same progress and cache as
  /// Download), then returns it as a share, or null when it did not load (the
  /// page says why).
  Future<ShareFile?> fileForConnectum() async {
    final l = current;
    final local = await ensure(l);
    if (local == null) return null;
    return ShareFile(name: l.file.name, path: local.path);
  }
}
