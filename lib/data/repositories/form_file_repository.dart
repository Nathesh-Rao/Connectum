import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../models/ids.dart';
import '../session_store.dart';
import 'attachment_repository.dart';

/// A file the server holds for a form's file field.
class FormUploadedFile {
  const FormUploadedFile({
    required this.id,
    required this.name,
    required this.size,
  });

  final String id;
  final String name;
  final int size;
}

/// Picking and uploading the files of a form's file field
/// (`POST /api/sd/files?name=...`, the bytes as the body). Picking and its
/// checks are the chat attachment's own; the form keeps the returned ids.
class FormFileRepository {
  FormFileRepository(this._attachments, this._session);

  final AttachmentRepository _attachments;
  final SessionStore _session;

  /// A photo from the library or the camera, or a document, checked against
  /// what the server takes. Null when the person backed out; throws
  /// [AttachmentException] for a file that would be refused.
  Future<PickedAttachment?> pick(AttachSource source) =>
      source == AttachSource.document
      ? _attachments.pickDocument()
      : _attachments.pick(source);

  Future<FormUploadedFile> upload(
    PickedAttachment file, {
    required void Function(double progress) onProgress,
    required CancelToken cancel,
  }) async {
    if (!AppConfig.isConfigured) {
      throw const AttachmentException('No server is set up for this build.');
    }
    if (file.bytes > AttachmentRepository.maxBlobBytes) {
      throw const AttachmentException(
        AttachmentRepository.tooLargeNotice,
        isRetryable: false,
      );
    }
    final token = _session.token;
    final origin = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    try {
      final response = await _attachments.dio.post<Object?>(
        '$origin/api/sd/files',
        queryParameters: {'name': file.name},
        data: File(file.path).openRead(),
        options: Options(
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            Headers.contentTypeHeader: file.mime,
            Headers.contentLengthHeader: file.bytes,
          },
          responseType: ResponseType.json,
        ),
        cancelToken: cancel,
        onSendProgress: (sent, total) {
          if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
        },
      );
      final data = response.data;
      final inner = data is Map ? data['data'] : null;
      final saved = inner is Map ? inner['file'] : null;
      final id = saved is Map ? idText(saved['id']) : '';
      if (id.isEmpty) {
        throw const AttachmentException(
          'The server gave an unexpected answer. Try again.',
        );
      }
      return FormUploadedFile(
        id: id,
        name: saved is Map && idText(saved['name']).isNotEmpty
            ? idText(saved['name'])
            : file.name,
        size: saved is Map ? intOf(saved['size']) : file.bytes,
      );
    } on DioException catch (e) {
      throw _fail(e);
    }
  }

  AttachmentException _fail(DioException e) {
    final status = e.response?.statusCode ?? 0;
    final body = e.response?.data;
    final error = body is Map && body['error'] is Map
        ? body['error'] as Map
        : {};
    final said = idText(error['message']);
    if (e.type == DioExceptionType.cancel) {
      return const AttachmentException('Cancelled.');
    }
    if (status == 401 || status == 403) {
      return const AttachmentException(
        'Your session has ended. Sign in again.',
        isRetryable: false,
      );
    }
    if (status == 413) {
      return const AttachmentException(
        AttachmentRepository.tooLargeNotice,
        isRetryable: false,
      );
    }
    if (status >= 400 && status < 500 && said.isNotEmpty) {
      return AttachmentException(said, isRetryable: false);
    }
    return AttachmentException(
      said.isNotEmpty ? said : "Couldn't upload that file. Try again.",
    );
  }
}
