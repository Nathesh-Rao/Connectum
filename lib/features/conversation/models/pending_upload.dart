import 'package:dio/dio.dart';
import 'package:get/get.dart';

import '../../../data/e2e/e2e_models.dart';
import '../../../data/repositories/attachment_repository.dart';

/// A photo or document on its way: shown at the end of the chat until the message that
/// carries it is written. Not stored; it lives with the conversation screen.
class PendingUpload {
  PendingUpload({
    required this.id,
    required this.file,
    this.replyTo,
    this.uploaded,
  });

  final String id;
  final PickedAttachment file;
  final String? replyTo;

  /// Set once the server has the file, so a retry after a failed send does not
  /// upload it again.
  UploadedFile? uploaded;

  /// The key and iv of the encrypted blob made for this file. Set once, then
  /// kept for every retry, so the blob that was uploaded stays openable.
  /// Null for a plain upload.
  String? e2eKey;
  String? e2eIv;

  /// The encrypted blob until the server has it (the same blob on a retry of
  /// a failed upload; dropped after).
  E2eEncryptedFile? sealed;

  bool get isEncrypted => e2eKey != null;

  CancelToken cancel = CancelToken();
  final progress = 0.0.obs;
  final isFailed = false.obs;
  final error = RxnString();
  final canRetry = true.obs;
}
