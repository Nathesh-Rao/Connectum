import 'dart:convert';

import 'chat_thread.dart';
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
    this.lastId = '',
    this.readId = '',
    this.unreadMore = false,
    this.isPinned = false,
    this.isMuted = false,
    this.deliveredId = '',
    this.peerReadId = '',
    this.peerDeliveredId = '',
    this.avatar,
    this.memberCount = 0,
    this.members = const [],
    this.owner = '',
    this.isListHidden = false,
    this.canRename = false,
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
  final String lastId;
  final String readId;

  /// The server counts at most 99 and says when there were more.
  final bool unreadMore;
  final bool isPinned;
  final bool isMuted;
  final String deliveredId;
  final String peerReadId;
  final String peerDeliveredId;
  final String? avatar;

  /// Members of a group, from the stored list (0 when not known).
  final int memberCount;

  /// Usernames of a group's members from the stored list (empty when not known).
  final List<String> members;

  /// A group's owner (the only one who may add people), empty when not known.
  final String owner;

  /// A record conversation whose form keeps it out of All and Direct & Teams
  /// (`record.names` `hidden`): it shows under Threads only.
  final bool isListHidden;

  /// A record conversation I saved the record of: I may rename it
  /// (`record.names` `canRename`).
  final bool canRename;

  /// "99+" past the cap, a plain number below it, nothing at 0.
  String get unreadLabel => unreadMore || unread > 99 ? '99+' : '$unread';

  bool get isEncryptedUnsupported => isEncrypted;

  Conversation withFlags({bool? isPinned, bool? isMuted}) =>
      _copy(isPinned: isPinned, isMuted: isMuted);

  Conversation withTitle(String title) => _copy(title: title);

  Conversation _copy({String? title, bool? isPinned, bool? isMuted}) =>
      Conversation(
        convId: convId,
        kind: kind,
        title: title ?? this.title,
        lastText: lastText,
        lastTs: lastTs,
        lastFrom: lastFrom,
        unread: unread,
        isArchived: isArchived,
        isEncrypted: isEncrypted,
        lastKind: lastKind,
        lastFormName: lastFormName,
        lastIsMine: lastIsMine,
        lastStatus: lastStatus,
        lastIsEncrypted: lastIsEncrypted,
        lastIsDeleted: lastIsDeleted,
        lastId: lastId,
        readId: readId,
        unreadMore: unreadMore,
        isPinned: isPinned ?? this.isPinned,
        isMuted: isMuted ?? this.isMuted,
        deliveredId: deliveredId,
        peerReadId: peerReadId,
        peerDeliveredId: peerDeliveredId,
        avatar: avatar,
        memberCount: memberCount,
        members: members,
        owner: owner,
        isListHidden: isListHidden,
        canRename: canRename,
      );

  /// The other person's username for a direct message.
  String? get peer => kind == 'dm' ? convId.substring(3) : null;

  factory Conversation.fromRow(Map<String, Object?> r) {
    final status = r['lm_status'] as String?;
    return Conversation(
      convId: idText(r['conv_id']),
      kind: idText(r['kind']),
      title: _title(r),
      lastText: r['lm_dstate'] == 'ok' && r['lm_plain'] != null
          ? idText(r['lm_plain'])
          : r['lm_text'] != null
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
          (intOf(r['lm_e2e']) == 1 && r['lm_dstate'] != 'ok') ||
          (r['lm_kind'] == null &&
              idText(r['last_text']) == '[encrypted message]'),
      lastIsDeleted: intOf(r['lm_deleted']) == 1,
      lastId: idText(r['last_id']),
      readId: idText(r['read_id']),
      unreadMore: intOf(r['unread_more']) == 1,
      isPinned: intOf(r['is_pinned']) == 1,
      isMuted: intOf(r['is_muted']) == 1,
      deliveredId: idText(r['delivered_id']),
      peerReadId: idText(r['peer_read_id']),
      peerDeliveredId: idText(r['peer_delivered_id']),
      avatar: r['avatar'] == null ? null : idText(r['avatar']),
      memberCount: _count(r['members_json'] as String?),
      members: _names(r['members_json'] as String?),
      owner: idText(r['owner']),
      isListHidden: intOf(r['is_list_hidden']) == 1,
      canRename: intOf(r['can_rename']) == 1,
    );
  }

  /// The title the server gave a shared thread (a record's, possibly renamed;
  /// a person's name or the organisation's), else the tidied group name, else
  /// the stored title.
  static String _title(Map<String, Object?> r) {
    final given = idText(r['thread_title']);
    if (given.isNotEmpty) return given;
    final title = idText(r['title']);
    return r['kind'] == 'group' ? ChatThread.fallbackTitle(title) : title;
  }

  static List<String> _names(String? json) {
    if (json == null) return const [];
    try {
      final members = jsonDecode(json);
      if (members is! List) return const [];
      return [
        for (final m in members)
          if (m is Map) idText(m['name'] ?? m['user']) else idText(m),
      ].where((n) => n.isNotEmpty).toList();
    } on FormatException {
      return const [];
    }
  }

  static int _count(String? json) {
    if (json == null) return 0;
    try {
      final members = jsonDecode(json);
      return members is List ? members.length : 0;
    } on FormatException {
      return 0;
    }
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
      other.lastIsDeleted == lastIsDeleted &&
      other.lastId == lastId &&
      other.unreadMore == unreadMore &&
      other.isPinned == isPinned &&
      other.isMuted == isMuted &&
      other.peerReadId == peerReadId &&
      other.peerDeliveredId == peerDeliveredId &&
      other.avatar == avatar &&
      other.memberCount == memberCount &&
      other.owner == owner &&
      other.isListHidden == isListHidden &&
      other.canRename == canRename;

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
    Object.hash(
      lastId,
      unreadMore,
      isPinned,
      isMuted,
      peerReadId,
      peerDeliveredId,
      avatar,
      memberCount,
      owner,
      isListHidden,
      canRename,
    ),
  );
}
