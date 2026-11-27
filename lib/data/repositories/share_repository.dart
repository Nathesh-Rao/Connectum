import '../../core/log/app_log.dart';
import '../models/conversation.dart';
import '../models/pending_upload.dart';
import '../socket/socket_service.dart';
import 'attachment_repository.dart';
import 'attachment_sender.dart';
import 'conversation_repository.dart';
import 'message_repository.dart';

/// A file on this phone that is offered to Connectum chats, with the name the
/// receiver sees.
class ShareFile {
  const ShareFile({required this.name, required this.path});

  final String name;
  final String path;
}

/// A chat the picker lists. A disabled one says why.
class ShareTarget {
  const ShareTarget(this.chat, {this.disabledReason});

  final Conversation chat;
  final String? disabledReason;

  bool get isEnabled => disabledReason == null;
}

/// How sharing to one chat ended.
class ShareResult {
  const ShareResult(this.chat, {this.problem, this.isRetryable = true});

  final Conversation chat;

  /// Null when the message is queued in the outbox (or already sent).
  final String? problem;
  final bool isRetryable;

  bool get isOk => problem == null;
}

/// "Share to Connectum": the chats a file can go to, and the send. A file goes
/// through [AttachmentSender], the same upload, encryption and outbox path as
/// a file attached in a chat; nothing here builds a tag or a request.
class ShareRepository {
  ShareRepository({
    required this.conversations,
    required this.sender,
    required this.attachments,
    required this.socket,
  });

  final ConversationRepository conversations;
  final AttachmentSender sender;
  final AttachmentRepository attachments;
  final SocketService socket;

  static const noFilesReason =
      'Files can be sent in direct messages and groups.';
  static const maxCaption = 500;
  int _seq = 0;

  bool get isOnline => socket.isOnline;

  MessageRepository get _messages => sender.messages;

  /// Reads the chat list again and returns it recent-first. Throws
  /// [StateError] when SQLite could not be read.
  Future<List<ShareTarget>> loadTargets() async {
    await conversations.reload();
    if (conversations.loadError.value != null) {
      throw StateError('chats not readable');
    }
    final rows = [...conversations.conversations]
      ..sort((a, b) => b.lastTs.compareTo(a.lastTs));
    return [
      for (final c in rows)
        ShareTarget(
          c,
          disabledReason: c.kind == 'dm' || c.kind == 'group'
              ? null
              : noFilesReason,
        ),
    ];
  }

  /// The files as chat attachments, checked by the chat rules. Throws
  /// [AttachmentException] for a type or size a chat refuses.
  Future<List<PickedAttachment>> prepare(List<ShareFile> files) => Future.wait([
    for (final f in files) attachments.describeFile(f.path, f.name),
  ]);

  /// Sends every file (and the caption, as a text) to each chat in turn. One
  /// chat failing never stops the others. A plain upload is made once and
  /// reused for every plain chat; a sealed chat gets its own sealed blob.
  Future<List<ShareResult>> send({
    required List<PickedAttachment> files,
    required List<Conversation> chats,
    String caption = '',
  }) async {
    final plain = <String, UploadedFile>{};
    final results = <ShareResult>[];
    final trimmed = caption.trim();
    final text = trimmed.length > maxCaption
        ? trimmed.substring(0, maxCaption)
        : trimmed;
    for (final chat in chats) {
      try {
        for (final file in files) {
          final upload = PendingUpload(
            id: 'share${_seq++}',
            file: file,
            uploaded: plain[file.path],
          );
          await sender.send(upload, chat.convId);
          if (!upload.isEncrypted && upload.uploaded != null) {
            plain[file.path] = upload.uploaded!;
          }
        }
        if (text.isNotEmpty) {
          final result = await _messages.sendText(chat.convId, text);
          if (result != SendResult.queued) {
            throw AttachmentException(
              _messages.lastBlock.isEmpty
                  ? "The note couldn't be sent."
                  : _messages.lastBlock,
            );
          }
        }
        results.add(ShareResult(chat));
      } on AttachmentException catch (e) {
        results.add(
          ShareResult(chat, problem: e.message, isRetryable: e.isRetryable),
        );
      } catch (e, st) {
        AppLog.e('share_repository', e, st);
        results.add(ShareResult(chat, problem: 'Could not be shared.'));
      }
    }
    return results;
  }
}
