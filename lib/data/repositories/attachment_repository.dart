import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

import '../../core/config/app_config.dart';
import '../session_store.dart';

enum AttachSource { library, camera, document }

/// A refused or failed attachment step, in words the person can read.
class AttachmentException implements Exception {
  const AttachmentException(this.message, {this.isRetryable = true});

  final String message;

  /// False when sending the same file again can never work.
  final bool isRetryable;

  @override
  String toString() => 'AttachmentException($message)';
}

class PickedAttachment {
  const PickedAttachment({
    required this.kind,
    required this.path,
    required this.name,
    required this.mime,
    required this.bytes,
  });

  /// The tag's kind: `image` or `file`.
  final String kind;
  final String path;
  final String name;
  final String mime;
  final int bytes;

  bool get isImage => kind == 'image';
}

class UploadedFile {
  const UploadedFile({required this.url, required this.type});

  /// Relative `/uploads/<name>`.
  final String url;
  final String type;
}

/// Picking a photo or a document and uploading it (`POST /upload`). The chat message that
/// carries the returned url goes through [MessageRepository].
class AttachmentRepository {
  AttachmentRepository(this._session) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      if (kDebugMode) {
        client.badCertificateCallback = (_, host, _) =>
            AppConfig.trustedHosts.contains(host);
      }
      return client;
    };
  }

  /// The server's limit for an image.
  static const maxImageBytes = 8 * 1024 * 1024;

  /// What the client sends at most, plain or encrypted, documents and blobs:
  /// the real ceiling is 10 MB (nginx `client_max_body_size`), with room for
  /// the request's own bytes.
  static const maxBlobBytes = 9961472;
  static const maxDocumentBytes = maxBlobBytes;

  /// What encryption adds to a file: the 16-byte GCM tag.
  static const blobOverhead = 16;

  static const tooLargeNotice =
      "Files over about 9.5 MB can't be sent right now";

  /// The generic type and neutral name an encrypted blob is uploaded under, so
  /// the server never sees the real name or type.
  static const blobMime = 'application/x-connectum-e2e';
  static const _blobName = 'attachment.e2e';

  /// The documents the server takes, with the mime it compares. Old Office
  /// formats, csv, zip and the like answer 415, so they are not offered.
  static const documentMimes = {
    'pdf': 'application/pdf',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
  };
  static const _allowed = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  final SessionStore _session;
  final _picker = ImagePicker();
  late final Dio _dio;

  /// The same client (certificate rules, timeouts) for downloads.
  Dio get dio => _dio;

  /// The photo the person chose, already compressed to JPEG by the picker
  /// (which also turns an iPhone HEIC into JPEG). Null when they backed out.
  /// Throws [AttachmentException] for a file the server would refuse.
  Future<PickedAttachment?> pick(AttachSource source) async {
    final XFile? file;
    try {
      file = await _picker.pickImage(
        source: source == AttachSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 2048,
        maxHeight: 2048,
      );
    } on Exception catch (_) {
      throw AttachmentException(
        source == AttachSource.camera
            ? "The camera isn't available."
            : "The photo library isn't available.",
      );
    }
    if (file == null) return null;
    final length = await file.length();
    final head = await file.openRead(0, 16).expand((b) => b).toList();
    final mime = lookupMimeType(file.path, headerBytes: head) ?? '';
    if (!_allowed.contains(mime)) {
      throw const AttachmentException(
        'Only JPEG, PNG, WebP or GIF photos can be sent.',
        isRetryable: false,
      );
    }
    if (length > maxImageBytes) {
      throw const AttachmentException(
        'That photo is larger than 8 MB.',
        isRetryable: false,
      );
    }
    if (length == 0) {
      throw const AttachmentException(
        "That photo couldn't be read.",
        isRetryable: false,
      );
    }
    return PickedAttachment(
      kind: 'image',
      path: file.path,
      name: file.name,
      mime: mime,
      bytes: length,
    );
  }

  /// The document the person chose, checked against what the server accepts
  /// (type, size, and the first bytes) so a refusal comes before the upload.
  /// Null when they backed out. Throws [AttachmentException] otherwise.
  Future<PickedAttachment?> pickDocument() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: documentMimes.keys.toList(),
      );
    } on Exception catch (_) {
      throw const AttachmentException("The file picker isn't available.");
    }
    if (picked == null) return null;
    final ext = p.extension(picked.name).replaceFirst('.', '').toLowerCase();
    final mime = documentMimes[ext];
    final path = picked.path;
    if (mime == null || path == null) {
      throw const AttachmentException(
        'Only PDF, Word, Excel, PowerPoint (.docx, .xlsx, .pptx) or text files can be sent.',
        isRetryable: false,
      );
    }
    final file = File(path);
    final length = await file.length();
    if (length == 0) {
      throw const AttachmentException(
        "That file couldn't be read.",
        isRetryable: false,
      );
    }
    if (length > maxDocumentBytes) {
      throw const AttachmentException(tooLargeNotice, isRetryable: false);
    }
    final head = await file.openRead(0, 8192).expand((b) => b).toList();
    if (!_looksLike(ext, head)) {
      throw AttachmentException(
        "That file doesn't look like a real .$ext file.",
        isRetryable: false,
      );
    }
    return PickedAttachment(
      kind: 'file',
      path: path,
      name: picked.name,
      mime: mime,
      bytes: length,
    );
  }

  /// The server's content check: `%PDF-`, a zip header for Office files, and
  /// text without a NUL byte.
  static bool _looksLike(String ext, List<int> head) {
    bool starts(List<int> magic) =>
        head.length >= magic.length &&
        [
          for (var i = 0; i < magic.length; i++) head[i] == magic[i],
        ].every((b) => b);
    return switch (ext) {
      'pdf' => starts([0x25, 0x50, 0x44, 0x46, 0x2D]),
      'txt' => !head.contains(0),
      _ => starts([0x50, 0x4B, 0x03, 0x04]),
    };
  }

  /// Uploads with real progress (0 to 1). The part is named `file`; the
  /// server takes the first part that has a file name.
  Future<UploadedFile> upload(
    PickedAttachment image, {
    required void Function(double progress) onProgress,
    required CancelToken cancel,
  }) async {
    if (!AppConfig.isConfigured) {
      throw const AttachmentException('No server is set up for this build.');
    }
    if (image.bytes > maxBlobBytes) {
      throw const AttachmentException(tooLargeNotice, isRetryable: false);
    }
    final token = _session.token;
    final origin = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _dio.post<Object?>(
        '$origin/upload',
        data: FormData.fromMap({
          'file': await MultipartFile.fromFile(
            image.path,
            filename: image.name,
            contentType: DioMediaType.parse(image.mime),
          ),
        }),
        options: Options(
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
        cancelToken: cancel,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
        },
      );
      final data = response.data;
      final url = data is Map ? data['url'] : null;
      if (url is! String || !url.startsWith('/uploads/')) {
        throw const AttachmentException(
          'The server gave an unexpected answer. Try again.',
        );
      }
      return UploadedFile(
        url: url,
        type: data is Map && data['type'] is String
            ? data['type'] as String
            : image.mime,
      );
    } on DioException catch (e) {
      throw _fail(e, image.isImage ? 'photo' : 'file');
    }
  }

  /// The size rules again for the encrypted blob, which is [blobOverhead]
  /// bytes longer than the file. Throws when the blob would be refused.
  void checkBlobSize(PickedAttachment file) {
    final blob = file.bytes + blobOverhead;
    if (blob > maxBlobBytes || (file.isImage && blob > maxImageBytes)) {
      throw AttachmentException(
        file.isImage ? 'That photo is larger than 8 MB.' : tooLargeNotice,
        isRetryable: false,
      );
    }
  }

  /// The picked file's bytes, to be encrypted. Never leaves the phone as they are.
  Future<Uint8List> readBytes(PickedAttachment file) async {
    try {
      return await File(file.path).readAsBytes();
    } on FileSystemException {
      throw const AttachmentException(
        "That file couldn't be read.",
        isRetryable: false,
      );
    }
  }

  /// Uploads an encrypted blob as `attachment.e2e` of type [blobMime], with
  /// real progress. The answer's url is the blob's address.
  Future<UploadedFile> uploadBlob(
    Uint8List blob, {
    required void Function(double progress) onProgress,
    required CancelToken cancel,
    required bool isImage,
  }) async {
    if (!AppConfig.isConfigured) {
      throw const AttachmentException('No server is set up for this build.');
    }
    if (blob.length > maxBlobBytes) {
      throw const AttachmentException(tooLargeNotice, isRetryable: false);
    }
    final token = _session.token;
    final origin = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _dio.post<Object?>(
        '$origin/upload',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            blob,
            filename: _blobName,
            contentType: DioMediaType.parse(blobMime),
          ),
        }),
        options: Options(
          headers: token == null ? null : {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
        ),
        cancelToken: cancel,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
        },
      );
      final data = response.data;
      final url = data is Map ? data['url'] : null;
      if (url is! String ||
          !url.startsWith('/uploads/') ||
          !url.endsWith('.e2e')) {
        throw const AttachmentException(
          'The server gave an unexpected answer. Try again.',
        );
      }
      return UploadedFile(url: url, type: blobMime);
    } on DioException catch (e) {
      throw _fail(e, isImage ? 'photo' : 'file');
    }
  }

  AttachmentException _fail(DioException e, String noun) {
    if (e.type == DioExceptionType.cancel) {
      return const AttachmentException('Cancelled.');
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final server = data is Map && data['error'] is String
        ? data['error'] as String
        : null;
    return switch (status) {
      401 => AttachmentException(
        server ?? 'Sign in again to send ${noun}s.',
        isRetryable: false,
      ),
      413 => AttachmentException(
        noun == 'photo'
            ? 'That photo is too large to send. The limit is about 10 MB.'
            : 'That file is too large to send. The limit is about 10 MB.',
        isRetryable: false,
      ),
      415 => AttachmentException(
        server ?? "That kind of $noun can't be sent.",
        isRetryable: false,
      ),
      429 => const AttachmentException(
        'Too many uploads. Wait a minute and try again.',
      ),
      int s when s >= 500 => AttachmentException(
        "The server couldn't save the $noun. Try again.",
      ),
      _ => AttachmentException(
        "The $noun couldn't be uploaded. Check your connection and try again.",
      ),
    };
  }
}
