import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../attachment_cache.dart';
import '../session_store.dart';
import '../smart_view/sv_file.dart';

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

/// Writes the bytes of [file] to [targetPath], reporting 0 to 1 when the
/// length is known. The real one is `GET /api/sd/files/<id>` with the Bearer
/// token; DEMO_MODE and tests pass their own.
typedef SvFileFetcher =
    Future<void> Function(
      SvFile file,
      String targetPath,
      void Function(double progress) onProgress,
      CancelToken cancel,
    );

/// Hands [bytes] to the system save dialog under [name]. Returns where the
/// person saved it, or null when they cancelled. Tests pass their own.
typedef SvFileSaver =
    Future<Uri?> Function(String name, Uint8List bytes, String mime);

/// The save dialog could not save the file (not a cancel).
class SvSaveException implements Exception {
  const SvSaveException();

  @override
  String toString() => 'SvSaveException';
}

/// Files of Smart View records: fetched with the session, kept as temp files
/// only (never in SQLite) keyed by id and size, 100 MB, least recently opened
/// first out, all gone on sign out or when the organisation changes. Only a
/// 24-hex file id from a row is ever requested.
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
    Future<Directory> Function()? tempDir,
    SvFileSaver? saver,
  }) : _token = token,
       _origin = origin.replaceAll(RegExp(r'/+$'), ''),
       _tempDir = tempDir ?? _defaultTemp,
       _saver = saver ?? _systemSaver {
    _fetcher = fetcher ?? _download;
    if (store != null) _worker = ever(store.current, (_) => clear());
  }

  static const maxCacheBytes = 100 * 1024 * 1024;

  /// Over this a file is not drawn in the viewer (Download still works).
  static const maxPreviewBytes = 25 * 1024 * 1024;
  static const textCapBytes = 200 * 1024;

  final Dio dio;
  final int cacheLimit;
  final AttachmentCache cache;
  final void Function() onUnauthorized;
  final String? Function() _token;
  final String _origin;
  final Future<Directory> Function() _tempDir;
  final SvFileSaver _saver;
  late final SvFileFetcher _fetcher;
  Worker? _worker;

  static Future<Directory> _defaultTemp() async => Directory(
    p.join((await getTemporaryDirectory()).path, 'sv_files'),
  ).create(recursive: true);

  static Future<Uri?> _systemSaver(String name, Uint8List bytes, String mime) =>
      FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mime);

  void dispose() => _worker?.dispose();

  String _cacheName(SvFile f) {
    final ext = SvFile.extensionOf(f.safeName);
    final clean = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? '.$ext' : '';
    return '${f.cacheKey}$clean';
  }

  /// The cached copy of [file], or null.
  Future<File?> cached(SvFile file) async {
    final target = File(p.join((await _tempDir()).path, _cacheName(file)));
    try {
      if (await target.exists() && await target.length() > 0) {
        await target.setLastModified(DateTime.now());
        return target;
      }
    } on FileSystemException {
      return null;
    }
    return null;
  }

  /// The file on the device: from the cache, else fetched.
  Future<File> fetch(
    SvFile file, {
    required void Function(double progress) onProgress,
    required CancelToken cancel,
  }) async {
    final hit = await cached(file);
    if (hit != null) {
      onProgress(1);
      return hit;
    }
    if (file.size > cacheLimit) {
      throw const SvFileException(
        SvFileProblem.tooLarge,
        'This file is too large to open here.',
      );
    }
    final dir = await _tempDir();
    final target = File(p.join(dir.path, _cacheName(file)));
    final part = File('${target.path}.part');
    try {
      await _fetcher(file, part.path, onProgress, cancel);
      if (!await part.exists() || await part.length() == 0) {
        throw const SvFileException(
          SvFileProblem.other,
          'The file came back empty.',
        );
      }
      await part.rename(target.path);
    } on DioException catch (e) {
      await _drop(part);
      throw _fail(e);
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
    await _evict(keep: target);
    return target;
  }

  Future<void> _download(
    SvFile file,
    String targetPath,
    void Function(double progress) onProgress,
    CancelToken cancel,
  ) async {
    final token = _token();
    await dio.download(
      '$_origin/api/sd/files/${file.id}',
      targetPath,
      cancelToken: cancel,
      options: Options(
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ),
      onReceiveProgress: (got, total) {
        final all = total > 0 ? total : file.size;
        if (all > 0) onProgress((got / all).clamp(0.0, 1.0));
      },
    );
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
      final bytes = await file.readAsBytes();
      where = await _saver(
        name,
        bytes,
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

  Future<void> _evict({required File keep}) async {
    try {
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final e in (await _tempDir()).list()) {
        if (e is! File || e.path.endsWith('.part')) continue;
        final stat = await e.stat();
        files.add((e, stat));
        total += stat.size;
      }
      if (total <= cacheLimit) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (f, stat) in files) {
        if (total <= cacheLimit) break;
        if (f.path == keep.path) continue;
        await _drop(f);
        total -= stat.size;
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
      return const SvFileException(
        SvFileProblem.forbidden,
        "You don't have access to this file.",
      );
    }
    if (status == 404) {
      return const SvFileException(
        SvFileProblem.notFound,
        'This file is no longer on the server.',
      );
    }
    if (status == 413) {
      return const SvFileException(
        SvFileProblem.tooLarge,
        'This file is too large to open here.',
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
