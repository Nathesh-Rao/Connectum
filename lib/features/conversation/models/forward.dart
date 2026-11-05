import 'package:get/get.dart';

import '../../../core/utils/attachment_tag.dart';
import '../../../core/utils/forwarded_text.dart';
import '../../../data/models/conversation.dart';
import '../../../data/models/message.dart';

/// What a forward is: an ordinary new message whose text starts with the
/// forward line (`CHAT_MESSAGE_UI_FOR_MOBILE.md`, section 3).
class Forward {
  Forward._();

  static const maxTargets = 5;

  /// Deleted, form, unreadable and not-sent messages are not forwarded, nor
  /// is a file whose blob has no key. A sealed file can be: its key and iv
  /// are in the tag, which is in the text we hold after decrypting, and the
  /// blob is not bound to the message (fixed AAD `e2e1-file`).
  static bool canForward(Message m) {
    if (m.isDeleted || m.kind == 'form' || m.status == MessageStatus.failed) {
      return false;
    }
    if (m.isEncryptedUnsupported) return false;
    final body = ForwardedText.parse(m.text).text.trim();
    final tag = AttachmentTag.parse(body);
    if (tag != null && tag.isUnreadable) return false;
    return body.isNotEmpty;
  }

  /// The attachment [m] carries, if any.
  static AttachmentTag? tagOf(Message m) =>
      AttachmentTag.parse(ForwardedText.parse(m.text).text);

  /// Where a message may go: a plain file only to plain chats, a sealed file
  /// only to encrypted ones (its key must never travel in plain text). Text
  /// goes anywhere the person can write.
  static bool canGoTo(Message m, Conversation c) {
    if (!(c.kind == 'dm' || c.kind == 'group' || c.kind == 'global')) {
      return false;
    }
    final tag = tagOf(m);
    if (tag == null) return true;
    return tag.isEncrypted ? c.isEncrypted : !c.isEncrypted;
  }

  /// "Photo · name" for the sheet.
  static String previewOf(Message m) {
    final tag = tagOf(m);
    if (tag == null) {
      final text = ForwardedText.parse(m.text).text.trim();
      return text.length > 80 ? '${text.substring(0, 80)}…' : text;
    }
    final kind = switch (tag.kind) {
      'image' => 'Photo',
      'video' => 'Video',
      'audio' => 'Voice note',
      _ => 'File',
    };
    return tag.name.isEmpty ? kind : '$kind · ${tag.name}';
  }

  /// The text to send. An earlier forward line is removed first and its
  /// original author kept; otherwise the author is [author] unless the
  /// message is mine. A file without a caption gets its name as the text.
  static String text(
    Message m, {
    required String forwarder,
    required String author,
  }) {
    final parsed = ForwardedText.parse(m.text, sender: m.sender);
    var body = parsed.text.trim();
    final tag = AttachmentTag.parse(body);
    if (tag != null && tag.caption.trim().isEmpty) {
      body = '${tag.name} $body';
    }
    final by = _clean(forwarder);
    var from = _clean(parsed.originalFrom ?? (m.isMine ? '' : author));
    if (from.toLowerCase() == by.toLowerCase()) from = '';
    return '↪ [Forwarded by $by${from.isEmpty ? '' : ' • from $from'}]: $body';
  }

  /// Names never carry the characters the line is read back with.
  static String _clean(String name) => name
      .replaceAll(RegExp(r'[•\]\[]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// The "Forward to" sheet's state: the search, the choice and the limit.
class ForwardPicker {
  ForwardPicker({required this.targets});

  final List<Conversation> targets;
  final query = ''.obs;
  final selected = <String>[].obs;
  final problem = RxnString();

  List<Conversation> get visible {
    final q = query.value.trim().toLowerCase();
    if (q.isEmpty) return targets;
    return [
      for (final c in targets)
        if (c.title.toLowerCase().contains(q) ||
            c.convId.toLowerCase().contains(q))
          c,
    ];
  }

  List<Conversation> get chosen => [
    for (final c in targets)
      if (selected.contains(c.convId)) c,
  ];

  String get sendLabel =>
      selected.isEmpty ? 'Send' : 'Send to ${selected.length}';

  void toggle(Conversation c) {
    problem.value = null;
    if (selected.remove(c.convId)) return;
    if (selected.length >= Forward.maxTargets) {
      problem.value = 'You can forward to up to ${Forward.maxTargets} chats.';
      return;
    }
    selected.add(c.convId);
  }
}
