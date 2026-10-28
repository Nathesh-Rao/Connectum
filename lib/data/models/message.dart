import 'ids.dart';

enum MessageStatus { pending, sending, sent, delivered, read, failed }

class Message {
  const Message({
    required this.msgId,
    required this.convId,
    required this.sender,
    required this.isMine,
    required this.text,
    required this.ts,
    required this.status,
    this.kind = 'chat',
    this.replyTo,
    this.isEncryptedUnsupported = false,
    this.editedTs,
    this.isDeleted = false,
    this.reactionsJson,
    this.formJson,
    this.failReason,
    this.localSeq = 0,
  });

  final String msgId;
  final String convId;
  final String sender;
  final bool isMine;
  final String kind;
  final String text;
  final int ts;
  final String? replyTo;
  final MessageStatus status;
  final bool isEncryptedUnsupported;
  final int? editedTs;
  final bool isDeleted;
  final String? reactionsJson;
  final String? formJson;
  final String? failReason;
  final int localSeq;

  bool get isLocalTemp => msgId.startsWith('temp-');

  factory Message.fromRow(Map<String, Object?> r) => Message(
    msgId: idText(r['msg_id']),
    convId: idText(r['conv_id']),
    sender: idText(r['sender']),
    isMine: intOf(r['is_mine']) == 1,
    kind: idText(r['kind']),
    text: idText(r['text']),
    ts: intOf(r['ts']),
    replyTo: r['reply_to'] == null ? null : idText(r['reply_to']),
    status: MessageStatus.values.firstWhere(
      (s) => s.name == r['status'],
      orElse: () => MessageStatus.sent,
    ),
    isEncryptedUnsupported: intOf(r['is_encrypted_unsupported']) == 1,
    editedTs: r['edited_ts'] == null ? null : intOf(r['edited_ts']),
    isDeleted: intOf(r['is_deleted']) == 1,
    reactionsJson: r['reactions_json'] as String?,
    formJson: r['form_json'] as String?,
    failReason: r['fail_reason'] as String?,
    localSeq: intOf(r['local_seq']),
  );
}
