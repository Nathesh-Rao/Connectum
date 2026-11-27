import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:get/get.dart' hide Response;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/log/app_log.dart';
import '../attachment_cache.dart';
import '../session_store.dart';
import '../smart_view/sv_file.dart';
import 'share_repository.dart';

enum SvFileProblem {
  network,
  forbidden,
  notFound,
  tooLarge,
  unauthorized,
  other,
}

class SvFileException implements Exception {
  const SvFileException(this.problem, this.message);

  final SvFileProblem problem;
  final String message;

  bool get isCancel =>
      problem == SvFileProblem.other && message == 'Cancelled.';

  @override
  String toString() => 'SvFileException($problem)';
}

/// What one request for a file answered: 200 (the bytes are in the target
/// file) or 304 (nothing written). [etag] is the bare 64-hex SHA-256 of a
/// strong `ETag` header, null for a weak or missing one.
class SvFileReply {
  const SvFileReply(this.status, {this.etag});

  final int status;
  final String? etag;
}

/// How far a network download is: the bytes received and the length the
/// server announced (0 when it did not say). Never goes backwards.
class SvFileProgress {
  const SvFileProgress(this.received, [this.total = 0]);

  static const none = SvFileProgress(0);

  final int received;
  final int total;

  bool get isStarted => received > 0;

  /// 0 to 1 (never above 1), or null while the length is unknown.
  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;

  /// "42% · 2.1 of 5.0 MB", or "2.1 MB" while the length is unknown; empty
  /// before the first byte.
  String get text {
    if (!isStarted) return '';
    final f = fraction;
    if (f == null) return SvFile.formatSize(received);
    final percent = (f * 100).floor().clamp(0, 100);
    final totalText = SvFile.formatSize(total);
    final unit = totalText.split(' ').last;
    final shown = math.min(received, total);
    final done = unit == 'MB'
        ? (shown / (1024 * 1024)).toStringAsFixed(1)
        : unit == 'KB'
        ? (shown / 1024).toStringAsFixed(total < 10 * 1024 ? 1 : 0)
        : '$shown';
    return '$percent% · $done of $totalText';
  }
}

/// One request for [file]: the real one is `GET /api/sd/files/<id>` with the
/// Bearer token and, when [etag] is not null, `If-None-Match`. It writes the
/// bytes to [targetPath] on 200 and reports 0 to 1 when the length is known;
/// a refusal is a [DioException] with a response. DEMO_MODE and tests pass
/// their own.
typedef SvFileFetcher =
    Future<SvFileReply> Function(
      SvFile file,
      String targetPath,
      String? etag,
      void Function(double progress) onProgress,
      CancelToken cancel,
    );

/// A file made local: [isMaybeStale] is true when the server could not be
/// reached and the kept copy is shown unchecked.
typedef SvFetched = ({File file, bool isMaybeStale});

/// `GET /api/sd/files/<id>/link` with a signed [url] (valid [expiresIn]
/// seconds, about 60).
class SvFileLink {
  const SvFileLink({required this.url, required this.expiresIn, this.etag});

  final String url;
  final int expiresIn;
  final String? etag;
}

/// Hands [file] (the cached copy) to the system save dialog under [name].
/// Returns where the person saved it, or null when they cancelled. Tests pass
/// their own.
typedef SvFileSaver =
    Future<Uri?> Function(String name, File file, String mime);

/// The save dialog could not save the file (not a cancel).
class SvSaveException implements Exception {
  const SvSaveException();

  @override
  String toString() => 'SvSaveException';
}

/// Files of Smart View records: fetched on tap with the session, kept as temp
/// files only (never in SQLite), named `<id>_<etag>` (the server's strong
/// SHA-256 ETag). Every open sends the request, with `If-None-Match` when a
/// copy is kept: 304 shows the kept bytes, 200 replaces them, 403 / 404 delete
/// them, a network failure keeps them and says they may be out of date. Only
/// strong ETags, files up to 10 MB, at most the newest 24 files and 30 MB; all
/// gone on sign out or when the organisation changes. Only a 24-hex file id
/// from a row is ever requested.
class SvFileRepository {
  SvFileRepository({
    required this.dio,
    required String? Function() token,
    required String origin,
    required this.cache,
    required this.onUnauthorized,
    SessionStore? store,
    SvFileFetcher? fetcher,
    this.cacheLimit = maxCacheBytes,
    this.cacheFiles = maxCacheFiles,
    Future<Directory> Function()? tempDir,
    SvFileSaver? saver,
    this.connectumShare,
  }) : _token = token,
       _origin = origin.replaceAll(RegExp(r'/+$'), ''),
       _tempDir = tempDir ?? _defaultTemp,
       _saver = saver ?? _systemSaver {
    _fetcher = fetcher ?? _download;
    if (store != null) _worker = ever(store.current, (_) => clear());
  }

  static const maxCacheBytes = 30 * 1024 * 1024;
  static const maxCacheFiles = 24;

  /// A file over this is shown but not kept.
  static const maxFileBytes = 10 * 1024 * 1024;

  /// Over this a file is not drawn in the viewer (Download still works).
  static const maxPreviewBytes = 25 * 1024 * 1024;
  static const textCapBytes = 200 * 1024;

  final Dio dio;

  /// "Share to Connectum"; null where sharing is not set up (the button is
  /// then not shown).
  final ShareRepository? connectumShare;
  final int cacheLimit;
  final int cacheFiles;
  final AttachmentCache cache;
  final void Function() onUnauthorized;
  final String? Function() _token;
  final String _origin;
  final Future<Directory> Function() _tempDir;
  final SvFileSaver _saver;
  late final SvFileFetcher _fetcher;
  Worker? _worker;
  final _running = <String, _Running>{};

  static Future<Directory> _defaultTemp() async => Directory(
    p.join((await getTemporaryDirectory()).path, 'sv_files'),
  ).create(recursive: true);

  /// `FilePicker.saveFile` only takes the bytes (the plugin writes them
  /// itself), so this is the one place the file is read whole, and only after
  /// the person has picked to save: the viewer caps files at 25 MB.
  static Future<Uri?> _systemSaver(String name, File file, String mime) async =>
      FilePicker.saveFile(
        fileName: name,
        bytes: await file.readAsBytes(),
        mimeType: mime,
      );

  void dispose() => _worker?.dispose();

  static final _heldName = RegExp(
    r'^([a-f0-9]{24})_([a-f0-9]{64})(\.[a-z0-9]{1,5})?$',
  );

  String _suffix(SvFile f) {
    final ext = SvFile.extensionOf(f.safeName);
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? '.$ext' : '';
  }

  /// The kept copy of [id]: its file and bare ETag, or null.
  Future<({File file, String etag})?> _held(String id) async {
    try {
      final dir = await _tempDir();
      if (!await dir.exists()) return null;
      ({File file, String etag, DateTime at})? best;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final m = _heldName.firstMatch(p.basename(e.path));
        if (m == null || m.group(1) != id) continue;
        final stat = await e.stat();
        if (stat.size == 0) continue;
        if (best == null || stat.modified.isAfter(best.at)) {
          best = (file: e, etag: m.group(2)!, at: stat.modified);
        }
      }
      return best == null ? null : (file: best.file, etag: best.etag);
    } on FileSystemException {
      return null;
    }
  }

  /// The file on the device. Always asks the server first (with
  /// `If-None-Match` when a copy is kept); two reads of the same file at once
  /// share one request.
  Future<SvFetched> fetch(
    SvFile file, {
    required void Function(double progress) onProgress,
    void Function(SvFileProgress progress)? onTransfer,
    required CancelToken cancel,
  }) {
    final running = _running[file.id];
    if (running != null) {
      running.listen(onProgress, onTransfer);
      return running.result;
    }
    final next = _Running(file)..listen(onProgress, onTransfer);
    next.result = _fetch(
      file,
      next.report,
      cancel,
    ).whenComplete(() => _running.remove(file.id));
    _running[file.id] = next;
    return next.result;
  }

  Future<SvFetched> _fetch(
    SvFile file,
    void Function(double) onProgress,
    CancelToken cancel,
  ) async {
    final clock = Stopwatch()..start();
    final held = await _held(file.id);
    final dir = await _tempDir();
    final part = File(p.join(dir.path, '${file.id}.part'));
    try {
      final reply = await _fetcher(
        file,
        part.path,
        held?.etag,
        onProgress,
        cancel,
      );
      if (reply.status == 304) {
        await _drop(part);
        if (held == null) {
          _log(file, 304, 0, 'unexpected', clock);
          throw const SvFileException(
            SvFileProblem.other,
            "The file couldn't be downloaded (unexpected answer).",
          );
        }
        try {
          await held.file.setLastModified(DateTime.now());
        } on FileSystemException {
          // The order of the cache is only a hint.
        }
        _log(file, 304, await held.file.length(), 'cache', clock);
        return (file: held.file, isMaybeStale: false);
      }
      if (!await part.exists() || await part.length() == 0) {
        throw const SvFileException(
          SvFileProblem.other,
          'The file came back empty.',
        );
      }
      final bytes = await part.length();
      final etag = reply.etag;
      final isKept = etag != null && bytes <= maxFileBytes;
      final target = File(
        p.join(dir.path, '${file.id}_${isKept ? etag : 'u'}${_suffix(file)}'),
      );
      await _dropAll(file.id);
      await part.rename(target.path);
      await _evict(keep: target);
      _log(file, 200, bytes, 'network', clock);
      return (file: target, isMaybeStale: false);
    } on DioException catch (e) {
      await _drop(part);
      final status = e.response?.statusCode;
      if (status == 403 || status == 404) await _dropAll(file.id);
      final failure = _fail(e);
      _log(file, status ?? 0, 0, failure.problem.name, clock);
      if (failure.problem == SvFileProblem.network && held != null) {
        return (file: held.file, isMaybeStale: true);
      }
      throw failure;
    } on FileSystemException {
      await _drop(part);
      throw const SvFileException(
        SvFileProblem.other,
        "The file couldn't be saved on this phone.",
      );
    } on SvFileException {
      await _drop(part);
      rethrow;
    }
  }

  void _log(SvFile f, int status, int bytes, String from, Stopwatch clock) =>
      AppLog.i(
        'sv_file',
        'file=${f.id} status=$status bytes=$bytes from=$from '
            'ms=${clock.elapsedMilliseconds}',
      );

  Future<SvFileReply> _download(
    SvFile file,
    String targetPath,
    String? etag,
    void Function(double progress) onProgress,
    CancelToken cancel,
  ) async {
    final token = _token();
    final res = await dio.get<ResponseBody>(
      '$_origin/api/sd/files/${file.id}',
      cancelToken: cancel,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          if (etag != null) 'If-None-Match': '"$etag"',
        },
      ),
    );
    final status = res.statusCode ?? 0;
    final body = res.data;
    if (status == 304) return SvFileReply(status);
    if (body == null || status != 200) {
      throw DioException(
        requestOptions: res.requestOptions,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: res.requestOptions,
          statusCode: status,
          data: body == null ? null : await _errorText(body),
        ),
      );
    }
    final total =
        int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
    final running = _running[file.id];
    final sink = File(targetPath).openWrite();
    var got = 0;
    try {
      await for (final chunk in body.stream) {
        if (cancel.isCancelled) {
          throw DioException(
            requestOptions: res.requestOptions,
            type: DioExceptionType.cancel,
          );
        }
        sink.add(chunk);
        got += chunk.length;
        if (running != null) {
          running.reportBytes(got, total);
        } else if (total > 0) {
          onProgress((got / total).clamp(0.0, 1.0));
        }
      }
    } on IOException {
      throw DioException(
        requestOptions: res.requestOptions,
        type: cancel.isCancelled
            ? DioExceptionType.cancel
            : DioExceptionType.connectionError,
      );
    } finally {
      await sink.close();
    }
    return SvFileReply(200, etag: _strongEtag(res.headers.value('etag')));
  }

  /// The bare 64-hex of a strong (quoted) ETag, else null.
  static String? _strongEtag(String? header) {
    final m = RegExp(r'^"([A-Fa-f0-9]{64})"$').firstMatch(header?.trim() ?? '');
    return m?.group(1)?.toLowerCase();
  }

  static Object? _decode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// The server's message from an error body (`{error:{message}}`,
  /// `{message}` or `{error:"..."}`), at most 200 characters, else null.
  Future<String?> _errorText(ResponseBody body) async {
    try {
      final bytes = <int>[];
      await for (final chunk in body.stream) {
        bytes.addAll(chunk);
        if (bytes.length > 4096) break;
      }
      final json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return messageOf(json);
    } on FormatException {
      return null;
    } on IOException {
      return null;
    }
  }

  static String? messageOf(Object? json) {
    if (json is! Map) return null;
    final error = json['error'];
    final text = switch (error) {
      Map() => error['message'],
      String() => error,
      _ => json['message'],
    };
    if (text is! String || text.trim().isEmpty) return null;
    final clean = text.trim();
    return clean.length > 200 ? clean.substring(0, 200) : clean;
  }

  /// `GET /api/sd/files/<id>/link`: a signed link (60 s) to open or share in
  /// another app, or null when the server has none (`url` is null for a file on
  /// its own disk: use [fetch]).
  Future<SvFileLink?> link(SvFile file) async {
    final token = _token();
    try {
      final res = await dio.get<Object?>(
        '$_origin/api/sd/files/${file.id}/link',
        options: Options(
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      var raw = res.data;
      if (raw is String) raw = _decode(raw);
      final body = raw is Map && raw['data'] is Map ? raw['data'] : raw;
      if (body is! Map) return null;
      final url = body['url'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
        return null;
      }
      final secs = body['expiresIn'];
      final tag = body['etag'];
      return SvFileLink(
        url: url as String,
        expiresIn: secs is num ? secs.toInt() : 60,
        etag: tag is String ? tag : null,
      );
    } on DioException catch (e) {
      throw _fail(e);
    }
  }

  /// The first [textCapBytes] of a text [file], decoded as UTF-8 (bad bytes
  /// become `?`), and whether the file is longer.
  Future<({String text, bool isCut})> readText(File file) async {
    final length = await file.length();
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, textCapBytes)) {
      bytes.addAll(chunk);
    }
    return (
      text: utf8.decode(bytes, allowMalformed: true),
      isCut: length > textCapBytes,
    );
  }

  /// True when [file] starts like a PNG, JPEG, GIF or WebP. The server sends
  /// every file as `application/octet-stream`, so a picture is drawn only
  /// when its first bytes say so (SVG never is).
  Future<bool> looksLikeImage(File file) async {
    final head = <int>[];
    await for (final chunk in file.openRead(0, 12)) {
      head.addAll(chunk);
    }
    return isImageHead(head);
  }

  /// True when `%PDF-` is among the first 1024 bytes.
  Future<bool> looksLikePdf(File file) async {
    final head = <int>[];
    await for (final chunk in file.openRead(0, 1024)) {
      head.addAll(chunk);
    }
    return latin1.decode(head, allowInvalid: true).contains('%PDF-');
  }

  static bool isImageHead(List<int> h) {
    bool starts(List<int> m, [int at = 0]) {
      if (h.length < at + m.length) return false;
      for (var i = 0; i < m.length; i++) {
        if (h[at + i] != m[i]) return false;
      }
      return true;
    }

    return starts([0x89, 0x50, 0x4E, 0x47]) ||
        starts([0xFF, 0xD8, 0xFF]) ||
        starts([0x47, 0x49, 0x46, 0x38]) ||
        (starts([0x52, 0x49, 0x46, 0x46]) &&
            starts([0x57, 0x45, 0x42, 0x50], 8));
  }

  /// Opens the system save dialog for [file] under the file's clean name; the
  /// system handles a name that is taken. Returns the name the person saved it
  /// under, or null when they cancelled. Throws [SvSaveException] when the
  /// copy could not be made; nothing is written outside what they picked.
  Future<String?> saveAs(SvFile source, File file) async {
    final name = source.safeName;
    final Uri? where;
    try {
      where = await _saver(
        name,
        file,
        source.mime.isEmpty ? 'application/octet-stream' : source.mime,
      );
    } on Object {
      throw const SvSaveException();
    }
    return where == null ? null : chosenName(where, name);
  }

  /// The file name in the [uri] the dialog returned (a `file:` path or a
  /// `content:` document id), else [fallback].
  static String chosenName(Uri uri, String fallback) {
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final name = last.split(RegExp(r'[/:]')).last.trim();
    return name.isEmpty ? fallback : name;
  }

  Future<OpenOutcome> open(File file) => cache.open(file);

  Future<void> share(File file, SvFile source) =>
      cache.share(file, source.safeName);

  /// Sign out and organisation change: every temp copy goes.
  Future<void> clear() async {
    try {
      final base = Directory(p.join((await _tempDir()).path));
      if (await base.exists()) await base.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  Future<void> _drop(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  /// Every kept copy of [id] (a refused or replaced file).
  Future<void> _dropAll(String id) async {
    try {
      final dir = await _tempDir();
      if (!await dir.exists()) return;
      await for (final e in dir.list()) {
        if (e is File && p.basename(e.path).startsWith('${id}_')) {
          await _drop(e);
        }
      }
    } on FileSystemException {
      return;
    }
  }

  /// Newest first; the rest go once there are more than [cacheFiles] files or
  /// [cacheLimit] bytes. [keep] always stays.
  Future<void> _evict({required File keep}) async {
    try {
      final files = <(File, FileStat)>[];
      await for (final e in (await _tempDir()).list()) {
        if (e is! File || e.path.endsWith('.part')) continue;
        files.add((e, await e.stat()));
      }
      files.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
      var count = 0;
      var total = 0;
      for (final (f, stat) in files) {
        final isKeep = f.path == keep.path;
        if (!isKeep &&
            (count >= cacheFiles || total + stat.size > cacheLimit)) {
          await _drop(f);
          continue;
        }
        count++;
        total += stat.size;
      }
    } on FileSystemException {
      return;
    }
  }

  SvFileException _fail(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return const SvFileException(SvFileProblem.other, 'Cancelled.');
    }
    final status = e.response?.statusCode;
    if (status == 401) {
      onUnauthorized();
      return const SvFileException(
        SvFileProblem.unauthorized,
        'Your session has ended. Sign in again.',
      );
    }
    if (status == 403) {
      return SvFileException(
        SvFileProblem.forbidden,
        _serverText(e) ?? "That file isn't available to you.",
      );
    }
    if (status == 404) {
      return SvFileException(
        SvFileProblem.notFound,
        _serverText(e) ?? 'No such file.',
      );
    }
    if (status == 413) {
      return SvFileException(
        SvFileProblem.tooLarge,
        _serverText(e) ?? 'That file is too large.',
      );
    }
    if (status == null &&
        (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.error is SocketException)) {
      return const SvFileException(
        SvFileProblem.network,
        'No connection. Check your internet and try again.',
      );
    }
    return SvFileException(
      SvFileProblem.other,
      status == null
          ? "The file couldn't be downloaded."
          : "The file couldn't be downloaded (error $status).",
    );
  }
}

String? _serverText(DioException e) {
  final data = e.response?.data;
  return data is String && data.isNotEmpty
      ? data
      : SvFileRepository.messageOf(data);
}

/// A request in flight for one file id and everyone waiting on it.
class _Running {
  _Running(this.file);

  final SvFile file;
  final _listeners = <void Function(double)>[];
  final _transfer = <void Function(SvFileProgress)>[];
  late final Future<SvFetched> result;
  SvFileProgress state = SvFileProgress.none;
  double _fraction = 0;

  /// A reader joins: it is told at once where the download is, so a late
  /// reader never starts from zero.
  void listen(
    void Function(double) onProgress,
    void Function(SvFileProgress)? onTransfer,
  ) {
    _listeners.add(onProgress);
    if (_fraction > 0) onProgress(_fraction);
    if (onTransfer != null) {
      _transfer.add(onTransfer);
      if (state.isStarted) onTransfer(state);
    }
  }

  /// A fetcher that only knows a share (the demo, tests).
  void report(double progress) {
    final p = progress.clamp(0.0, 1.0).toDouble();
    if (p <= _fraction) return;
    _fraction = p;
    for (final l in List.of(_listeners)) {
      l(p);
    }
    if (file.size > 0) {
      reportBytes((p * file.size).round(), file.size, isFraction: false);
    }
  }

  /// The real download: bytes so far and the announced length (0: unknown).
  void reportBytes(int received, int total, {bool isFraction = true}) {
    if (received <= state.received) return;
    final next = SvFileProgress(received, total);
    state = next;
    for (final l in List.of(_transfer)) {
      l(next);
    }
    final f = next.fraction;
    if (isFraction && f != null && f > _fraction) {
      _fraction = f;
      for (final l in List.of(_listeners)) {
        l(f);
      }
    }
  }
}
