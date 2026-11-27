import 'dart:typed_data';

import '../../core/log/app_log.dart';
import '../../core/utils/attachment_tag.dart';
import '../models/pending_upload.dart';
import 'attachment_repository.dart';
import 'e2e_repository.dart';
import 'message_repository.dart';

/// The one way a file goes into a chat: ask the policy how it must travel,
/// seal it first when the thread is encrypted, upload it, then send the tag
/// through the outbox like any message. The conversation screen and
/// "Share to Connectum" both use it.
class AttachmentSender {
  AttachmentSender({
    required this.messages,
    required this.attachments,
    required this.e2e,
  });

  final MessageRepository messages;
  final AttachmentRepository attachments;
  final E2eRepository e2e;

  /// Makes sure the server holds [upload]'s file in the form [convId] needs.
  /// The thread is asked again every time: a blob made for another answer
  /// (plain for an encrypted thread, or the reverse) is dropped, never sent.
  Future<void> uploadFor(PendingUpload upload, String convId) async {
    final mode = await messages.attachMode(convId);
    if (mode == null) throw AttachmentException(messages.lastBlock);
    final isSealed = mode == AttachMode.encrypted;
    if (upload.isEncrypted != isSealed) {
      upload.uploaded = null;
      upload.e2eKey = null;
      upload.e2eIv = null;
      upload.sealed = null;
    }
    if (upload.uploaded != null) return;
    if (!isSealed) {
      upload.uploaded = await attachments.upload(
        upload.file,
        onProgress: (p) => upload.progress.value = p,
        cancel: upload.cancel,
      );
      return;
    }
    attachments.checkBlobSize(upload.file);
    var sealed = upload.sealed;
    if (sealed == null) {
      final bytes = await attachments.readBytes(upload.file);
      try {
        sealed = await e2e.encryptFile(bytes);
      } catch (e, st) {
        AppLog.e('attachment_sender', e, st);
        throw const AttachmentException(
          "That file couldn't be encrypted. Try again.",
        );
      }
      upload.sealed = sealed;
      upload.e2eKey = sealed.key;
      upload.e2eIv = sealed.iv;
    }
    upload.uploaded = await attachments.uploadBlob(
      Uint8List.fromList(sealed.ciphertext),
      onProgress: (p) => upload.progress.value = p,
      cancel: upload.cancel,
      isImage: upload.file.isImage,
    );
    upload.sealed = null;
  }

  /// The tag of an uploaded [upload].
  static AttachmentTag tagOf(PendingUpload upload) => AttachmentTag(
    kind: upload.file.kind,
    name: upload.file.name,
    size: AttachmentTag.sizeText(upload.file.bytes),
    url: upload.uploaded!.url,
    type: upload.file.mime,
    e2eKey: upload.e2eKey,
    e2eIv: upload.e2eIv,
  );

  /// Uploads, then queues the tag message in [convId]. Throws
  /// [AttachmentException] when the file cannot go there.
  Future<void> send(PendingUpload upload, String convId) async {
    await uploadFor(upload, convId);
    upload.progress.value = 1;
    final result = await messages.sendAttachment(
      convId,
      tagOf(upload),
      replyTo: upload.replyTo,
    );
    switch (result) {
      case SendResult.queued:
        return;
      case SendResult.blocked:
        throw AttachmentException(messages.lastBlock);
      case SendResult.tooLong:
      case SendResult.invalid:
      case SendResult.noSession:
        throw AttachmentException(
          "That ${upload.file.isImage ? 'photo' : 'file'} couldn't be sent.",
        );
    }
  }
}
