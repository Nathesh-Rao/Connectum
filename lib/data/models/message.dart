import '../e2e/e2e_models.dart';
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
    this.isEncrypted = false,
    this.decryptState,
    this.unreadableCode,
    this.editedTs,
    this.isDeleted = false,
    this.reactionsJson,
    this.formJson,
    this.failReason,
    this.localSeq = 0,
    this.cid,
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

  /// The server flagged the text as an end-to-end envelope. [text] is then the
  /// decrypted text when [decryptState] is `ok`, else the envelope.
  final bool isEncrypted;

  /// `ok`, `cant_decrypt` or `pending`; null for a plain message.
  final String? decryptState;

  /// Why an envelope could not be opened (the code kept in `plaintext` of a
  /// `cant_decrypt` row); null when unknown, e.g. a row from before it was kept.
  final String? unreadableCode;
  final int? editedTs;
  final bool isDeleted;
  final String? reactionsJson;
  final String? formJson;
  final String? failReason;
  final int localSeq;
  final String? cid;

  bool get isDecrypting => isEncrypted && decryptState == 'pending';

  /// Encrypted and not readable on this device (yet).
  bool get isEncryptedUnsupported => isEncrypted && decryptState != 'ok';

  /// Why an encrypted send failed, in plain words; null for other failures.
  String? get secureFailure {
    final reason = failReason;
    return reason != null && reason.startsWith(E2eSendDecision.failTag)
        ? reason.substring(E2eSendDecision.failTag.length)
        : null;
  }

  bool get isLocalTemp => msgId.startsWith('temp-');

  Message copyWith({
    String? msgId,
    MessageStatus? status,
    bool? isDeleted,
    String? failReason,
    String? reactionsJson,
  }) => Message(
    msgId: msgId ?? this.msgId,
    convId: convId,
    sender: sender,
    isMine: isMine,
    text: text,
    ts: ts,
    status: status ?? this.status,
    kind: kind,
    replyTo: replyTo,
    isEncrypted: isEncrypted,
    decryptState: decryptState,
    unreadableCode: unreadableCode,
    editedTs: editedTs,
    isDeleted: isDeleted ?? this.isDeleted,
    reactionsJson: reactionsJson ?? this.reactionsJson,
    formJson: formJson,
    failReason: failReason ?? this.failReason,
    localSeq: localSeq,
    cid: cid,
  );

  factory Message.fromRow(Map<String, Object?> r) => Message(
    msgId: idText(r['msg_id']),
    convId: idText(r['conv_id']),
    sender: idText(r['sender']),
    isMine: intOf(r['is_mine']) == 1,
    kind: idText(r['kind']),
    text: r['decrypt_state'] == 'ok' && r['plaintext'] != null
        ? idText(r['plaintext'])
        : idText(r['text']),
    ts: intOf(r['ts']),
    replyTo: r['reply_to'] == null ? null : idText(r['reply_to']),
    status: MessageStatus.values.firstWhere(
      (s) => s.name == r['status'],
      orElse: () => MessageStatus.sent,
    ),
    isEncrypted: intOf(r['is_encrypted_unsupported']) == 1,
    decryptState: r['decrypt_state'] as String?,
    unreadableCode:
        r['decrypt_state'] == 'cant_decrypt' && r['plaintext'] != null
        ? idText(r['plaintext'])
        : null,
    editedTs: r['edited_ts'] == null ? null : intOf(r['edited_ts']),
    isDeleted: intOf(r['is_deleted']) == 1,
    reactionsJson: r['reactions_json'] as String?,
    formJson: r['form_json'] as String?,
    failReason: r['fail_reason'] as String?,
    localSeq: intOf(r['local_seq']),
    cid: r['cid'] as String?,
  );
}
