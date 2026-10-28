import 'dart:convert';

import 'ids.dart';
import 'message.dart';

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
    this.lastKind = 'chat',
    this.lastFormName,
    this.lastIsMine = false,
    this.lastStatus,
    this.lastIsEncrypted = false,
    this.lastIsDeleted = false,
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
  final String lastKind;
  final String? lastFormName;
  final bool lastIsMine;
  final MessageStatus? lastStatus;
  final bool lastIsEncrypted;
  final bool lastIsDeleted;

  bool get isEncryptedUnsupported => isEncrypted;

  /// The other person's username for a direct message.
  String? get peer => kind == 'dm' ? convId.substring(3) : null;

  factory Conversation.fromRow(Map<String, Object?> r) {
    final status = r['lm_status'] as String?;
    return Conversation(
      convId: idText(r['conv_id']),
      kind: idText(r['kind']),
      title: idText(r['title']),
      lastText: r['lm_text'] != null
          ? idText(r['lm_text'])
          : idText(r['last_text']),
      lastTs: intOf(r['last_ts']),
      lastFrom: idText(r['last_from']),
      unread: intOf(r['unread']),
      isArchived: intOf(r['is_archived']) == 1,
      isEncrypted: intOf(r['is_encrypted']) == 1,
      lastKind: r['lm_kind'] == null ? 'chat' : idText(r['lm_kind']),
      lastFormName: _formName(r['lm_form'] as String?),
      lastIsMine: intOf(r['lm_mine']) == 1,
      lastStatus: status == null
          ? null
          : MessageStatus.values.firstWhere(
              (s) => s.name == status,
              orElse: () => MessageStatus.sent,
            ),
      lastIsEncrypted:
          intOf(r['lm_e2e']) == 1 ||
          (r['lm_kind'] == null && intOf(r['is_encrypted']) == 1),
      lastIsDeleted: intOf(r['lm_deleted']) == 1,
    );
  }

  /// A form card is named by its caption, then its structure, then "Form".
  static String? _formName(String? json) {
    if (json == null) return null;
    try {
      final form = jsonDecode(json);
      if (form is! Map) return 'Form';
      final caption = idText(form['caption']);
      if (caption.isNotEmpty) return caption;
      final structure = idText(form['structure']);
      return structure.isNotEmpty ? structure : 'Form';
    } on FormatException {
      return 'Form';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Conversation &&
      other.convId == convId &&
      other.kind == kind &&
      other.title == title &&
      other.lastText == lastText &&
      other.lastTs == lastTs &&
      other.lastFrom == lastFrom &&
      other.unread == unread &&
      other.isArchived == isArchived &&
      other.isEncrypted == isEncrypted &&
      other.lastKind == lastKind &&
      other.lastFormName == lastFormName &&
      other.lastIsMine == lastIsMine &&
      other.lastStatus == lastStatus &&
      other.lastIsEncrypted == lastIsEncrypted &&
      other.lastIsDeleted == lastIsDeleted;

  @override
  int get hashCode => Object.hash(
    convId,
    kind,
    title,
    lastText,
    lastTs,
    lastFrom,
    unread,
    isArchived,
    isEncrypted,
    lastKind,
    lastFormName,
    lastIsMine,
    lastStatus,
    lastIsEncrypted,
    lastIsDeleted,
  );
}
