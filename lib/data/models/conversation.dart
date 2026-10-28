import 'ids.dart';

class Conversation {
  const Conversation({
    required this.convId,
    required this.kind,
    required this.title,
    this.lastText = '',
    this.lastTs = 0,
    this.lastFrom = '',
    this.unread = 0,
    this.isArchived = false,
    this.isEncrypted = false,
  });

  final String convId;
  final String kind;
  final String title;
  final String lastText;
  final int lastTs;
  final String lastFrom;
  final int unread;
  final bool isArchived;
  final bool isEncrypted;

  bool get isEncryptedUnsupported => isEncrypted;

  factory Conversation.fromRow(Map<String, Object?> r) => Conversation(
    convId: idText(r['conv_id']),
    kind: idText(r['kind']),
    title: idText(r['title']),
    lastText: idText(r['last_text']),
    lastTs: intOf(r['last_ts']),
    lastFrom: idText(r['last_from']),
    unread: intOf(r['unread']),
    isArchived: intOf(r['is_archived']) == 1,
    isEncrypted: intOf(r['is_encrypted']) == 1,
  );
}
