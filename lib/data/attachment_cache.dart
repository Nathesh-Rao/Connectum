import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/attachment_tag.dart';
import 'repositories/attachment_repository.dart';

enum OpenOutcome { opened, noApp, failed }

/// Downloaded chat files, kept in the app's support directory under
/// `attachments/`. The file name on disk is built only from the server's
/// random name in `/uploads/<name>` and a checked extension; the sender's file
/// name is never part of a path. Capped at [maxBytes]: the files opened longest
/// ago go first.
class AttachmentCache {
  AttachmentCache(this._dio);

  static const maxBytes = 200 * 1024 * 1024;
  static const _staleDownload = Duration(days: 1);

  /// What the server stores (`chat_web_upload.erl`). An extension outside this
  /// list is never written to disk, so a file named `x.apk` stays `x`.
  static const _extensions = {
    'png',
    'jpg',
    'gif',
    'webp',
    'pdf',
    'docx',
    'xlsx',
    'pptx',
    'txt',
    'mp4',
    'mov',
    'webm',
    'm4a',
    'ogg',
  };

  /// What the server stores an encrypted blob as.
  static const _blobExtension = 'e2e';
  static const _openTmp = 'open-tmp';
  static final _serverName = RegExp(
    r'^([A-Za-z0-9_-]{1,128})(?:\.([A-Za-z0-9]{1,5}))?$',
  );

  final Dio _dio;
  Directory? _folder;

  /// The cache file name for [tag], or null when its url is not a plain
  /// `/uploads/<name>` (another folder, a `..`, a slash or odd characters in
  /// the name). The random part of the server name, plus the extension of the
  /// original name when that is a known one, else the server name's own.
  static String? keyFor(AttachmentTag tag) {
    var path = tag.url;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      path = Uri.tryParse(path)?.path ?? '';
    }
    const prefix = '/uploads/';
    if (!path.startsWith(prefix)) return null;
    final match = _serverName.firstMatch(path.substring(prefix.length));
    if (match == null) return null;
    final fromName = _extensionOf(tag.name);
    final fromUrl = (match.group(2) ?? '').toLowerCase();
    // An encrypted blob is stored under its own name, never under the real
    // file's extension, so it can never be mistaken for the file.
    if (tag.isEncrypted) {
      return fromUrl == _blobExtension
          ? '${match.group(1)}.$_blobExtension'
          : match.group(1)!;
    }
    final ext = _extensions.contains(fromName)
        ? fromName
        : _extensions.contains(fromUrl)
        ? fromUrl
        : '';
    return ext.isEmpty ? match.group(1)! : '${match.group(1)}.$ext';
  }

  static String _extensionOf(String name) {
    final last = name.split(RegExp(r'[/\\]')).last;
    final dot = last.lastIndexOf('.');
    return dot < 0 ? '' : last.substring(dot + 1).toLowerCase();
  }

  Future<Directory> _directory() async {
    final existing = _folder;
    if (existing != null && existing.existsSync()) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    await dir.create(recursive: true);
    if (Platform.isIOS) {
      // Re-downloadable, so kept out of iCloud and device backups.
      try {
        await const MethodChannel(
          'connectum/device',
        ).invokeMethod<bool>('excludeFromBackup', dir.path);
      } catch (_) {}
    }
    return _folder = dir;
  }

  /// The stored file for [tag], or null when it is not cached.
  Future<File?> cached(AttachmentTag tag) async {
    final key = keyFor(tag);
    if (key == null) return null;
    final file = File(p.join((await _directory()).path, key));
    try {
      if (await file.exists() && await file.length() > 0) return file;
    } on FileSystemException {
      return null;
    }
    return null;
  }

  /// Marks [file] as opened just now, so eviction keeps it longest.
  Future<void> touch(File file) async {
    try {
      await file.setLastModified(DateTime.now());
    } on FileSystemException {
      return;
    }
  }

  /// Downloads [tag]'s file into the cache with progress (0 to 1, only when the
  /// server says the length). Only a chat upload on this server is fetched.
  Future<File> fetch(
    AttachmentTag tag, {
    required void Function(double progress) onProgress,
    required CancelToken cancel,
  }) async {
    final key = keyFor(tag);
    final url = tag.resolvedUrl;
    if (key == null || url == null) {
      throw const AttachmentException(
        "This file can't be opened here.",
        isRetryable: false,
      );
    }
    final dir = await _directory();
    final target = File(p.join(dir.path, key));
    final part = File('${target.path}.part');
    try {
      await _dio.download(
        url,
        part.path,
        cancelToken: cancel,
        onReceiveProgress: (got, total) {
          if (total > 0) onProgress((got / total).clamp(0.0, 1.0));
        },
      );
      if (await part.length() == 0) {
        throw const AttachmentException('The file came back empty.');
      }
      await part.rename(target.path);
    } on DioException catch (e) {
      await _drop(part);
      throw _fail(e);
    } on FileSystemException {
      await _drop(part);
      throw const AttachmentException(
        "The file couldn't be saved on this phone.",
      );
    } on AttachmentException {
      await _drop(part);
      rethrow;
    }
    await _evict(keep: target);
    return target;
  }

  /// Hands [file] to the system viewer.
  Future<OpenOutcome> open(File file) async {
    await touch(file);
    try {
      final result = await OpenFilex.open(file.path);
      return switch (result.type) {
        ResultType.done => OpenOutcome.opened,
        ResultType.noAppToOpen => OpenOutcome.noApp,
        _ => OpenOutcome.failed,
      };
    } catch (_) {
      return OpenOutcome.failed;
    }
  }

  /// Hands [file] to the system share sheet (share or save), under the
  /// sender's file name.
  Future<void> share(File file, String name) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], fileNameOverrides: [name]),
      );
    } catch (_) {
      return;
    }
  }

  /// Sign out and `session_replaced`: every cached file goes, and so does
  /// every decrypted copy made for opening.
  Future<void> clear() async {
    _folder = null;
    await clearOpenTmp();
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'attachments'));
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  /// Deletes the decrypted documents handed to the system viewer. Called at
  /// app start, on sign out and on `session_replaced`.
  Future<void> clearOpenTmp() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, _openTmp));
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  /// The encrypted blob stored for [tag], or null when it is not cached or
  /// shorter than a GCM tag (never a partial result).
  Future<Uint8List?> readBlob(AttachmentTag tag) async {
    final file = await cached(tag);
    if (file == null) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.length < 16 ? null : bytes;
    } on FileSystemException {
      return null;
    }
  }

  /// Removes the stored blob of [tag] (it did not decrypt, so the next try
  /// downloads it again).
  Future<void> forget(AttachmentTag tag) async {
    final file = await cached(tag);
    if (file != null) await _drop(file);
  }

  /// Writes the decrypted [bytes] of a document to `open-tmp/<random>/` just
  /// before the viewer opens it. The folder is random; the file name is the
  /// sender's name cleaned to plain characters with a known extension. Null
  /// when the name has no extension a document can have.
  Future<File?> writeForOpening(String name, Uint8List bytes) async {
    final ext = _extensionOf(name);
    if (!AttachmentRepository.documentMimes.containsKey(ext)) return null;
    final stem = p
        .basenameWithoutExtension(name.split(RegExp(r'[/\\]')).last)
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._()-]'), '_')
        .replaceAll(RegExp(r'^\.+'), '_');
    final shown = stem.isEmpty ? 'file' : stem;
    final random = Random.secure();
    final id = [
      for (var i = 0; i < 8; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _openTmp, id));
    final file = File(
      p.join(
        dir.path,
        '${shown.length > 60 ? shown.substring(0, 60) : shown}.$ext',
      ),
    );
    try {
      await dir.create(recursive: true);
      if (Platform.isIOS) {
        try {
          await const MethodChannel(
            'connectum/device',
          ).invokeMethod<bool>('excludeFromBackup', dir.parent.path);
        } catch (_) {}
      }
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on FileSystemException {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } on FileSystemException {
        return null;
      }
      return null;
    }
  }

  Future<void> _drop(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      return;
    }
  }

  /// Over [maxBytes]: deletes the least recently opened files, never [keep].
  /// A half-finished download older than a day is removed on the way.
  Future<void> _evict({required File keep}) async {
    try {
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final entry in (await _directory()).list()) {
        if (entry is! File) continue;
        final stat = await entry.stat();
        if (entry.path.endsWith('.part')) {
          if (DateTime.now().difference(stat.modified) > _staleDownload) {
            await _drop(entry);
          }
          continue;
        }
        files.add((entry, stat));
        total += stat.size;
      }
      if (total <= maxBytes) return;
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in files) {
        if (total <= maxBytes) break;
        if (file.path == keep.path) continue;
        await _drop(file);
        total -= stat.size;
      }
    } on FileSystemException {
      return;
    }
  }

  AttachmentException _fail(DioException e) {
    if (e.type == DioExceptionType.cancel) {
      return const AttachmentException('Cancelled.');
    }
    final status = e.response?.statusCode;
    if (status == 404) {
      return const AttachmentException('This file is no longer on the server.');
    }
    if (status == null &&
        (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.error is SocketException)) {
      return const AttachmentException(
        'No connection. Check your internet and try again.',
      );
    }
    return AttachmentException(
      status == null
          ? "The file couldn't be downloaded."
          : "The file couldn't be downloaded (error $status).",
    );
  }
}
