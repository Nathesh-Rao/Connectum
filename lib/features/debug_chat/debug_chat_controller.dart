import 'package:get/get.dart';

import '../../core/utils/attachment_tag.dart';
import '../../core/utils/chat_time.dart';
import '../../core/utils/mention_text.dart';
import '../../data/models/message.dart';
import '../conversation/models/chat_item.dart';
import '../conversation/models/document_info.dart';

/// Sample messages for the message rules: mentions, forwards, edits, a reply
/// with a missing original, a deleted message (must not show), day separators.
class DebugChatController extends GetxController {
  static const me = 'me';

  /// Known: ann (named), bob, me. "zed" is unknown and stays as typed.
  static const people = MentionPeople(
    me: me,
    names: {'ann': 'Ann Rao', 'bob': 'bob', 'me': 'me'},
  );

  late final List<ChatItem> items = _build();

  static AttachmentTag _doc(
    String name,
    String size,
    String type, {
    bool isEncrypted = false,
  }) => AttachmentTag(
    kind: 'file',
    name: name,
    size: size,
    url: '/uploads/sample-$name',
    type: type,
    e2eKey: isEncrypted ? 'k' : null,
    e2eIv: isEncrypted ? 'i' : null,
  );

  /// Document cards and the state each starts in. No server: a tap on a
  /// sample only plays the states.
  static final documents = <(AttachmentTag, DocumentButtonState, double)>[
    (
      _doc('Quarterly report.pdf', '2.4 MB', 'application/pdf'),
      DocumentButtonState.idle,
      0,
    ),
    (
      _doc(
        'Contract draft.docx',
        '86 KB',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      ),
      DocumentButtonState.downloading,
      0.42,
    ),
    (
      _doc(
        'Budget 2026 with a really long file name for the check.xlsx',
        '1.1 MB',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      DocumentButtonState.done,
      0,
    ),
    (
      _doc('photos.zip', '18.2 MB', 'application/zip'),
      DocumentButtonState.failed,
      0,
    ),
    (
      _doc('Payslip.pdf', '240 KB', 'application/pdf', isEncrypted: true),
      DocumentButtonState.idle,
      0,
    ),
    (
      _doc(
        'Payslip (downloading).pdf',
        '240 KB',
        'application/pdf',
        isEncrypted: true,
      ),
      DocumentButtonState.downloading,
      0,
    ),
    (
      _doc(
        'Payslip (failed).pdf',
        '240 KB',
        'application/pdf',
        isEncrypted: true,
      ),
      DocumentButtonState.failed,
      0,
    ),
    (
      _doc(
        'Payslip (downloaded).pdf',
        '240 KB',
        'application/pdf',
        isEncrypted: true,
      ),
      DocumentButtonState.done,
      0,
    ),
  ];

  final states = <String, DocumentButtonState>{}.obs;
  final progress = <String, double>{}.obs;

  @override
  void onInit() {
    super.onInit();
    for (final (tag, state, value) in documents) {
      states[tag.url] = state;
      progress[tag.url] = value;
    }
  }

  DocumentButtonState stateOf(AttachmentTag tag) =>
      states[tag.url] ?? DocumentButtonState.idle;

  /// Plays idle -> downloading -> downloaded; a failed one retries the same.
  Future<void> play(AttachmentTag tag) async {
    states[tag.url] = DocumentButtonState.downloading;
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (states[tag.url] != DocumentButtonState.downloading) return;
      progress[tag.url] = i / 10;
    }
    states[tag.url] = DocumentButtonState.done;
  }

  void cancel(AttachmentTag tag) {
    states[tag.url] = DocumentButtonState.idle;
    progress[tag.url] = 0;
  }

  Message _m(
    String id,
    String sender,
    String text,
    int daysAgo, {
    String? replyTo,
    int? editedTs,
    bool isDeleted = false,
  }) {
    final ts = DateTime.now()
        .subtract(Duration(days: daysAgo, minutes: int.parse(id)))
        .millisecondsSinceEpoch;
    return Message(
      msgId: id,
      convId: 'group:demo',
      sender: sender,
      isMine: sender == me,
      text: text,
      ts: ts,
      status: MessageStatus.read,
      replyTo: replyTo,
      editedTs: editedTs,
      isDeleted: isDeleted,
    );
  }

  List<ChatItem> _build() {
    final samples = [
      _m('9', 'ann', 'Older day: hello @bob, welcome', 9),
      _m('8', 'bob', 'Hi @Ann.', 3),
      _m('7', 'ann', 'Ping @me, and @zed (unknown), mail a@b.com', 1),
      _m('6', me, '(@ann) @a x @ann-', 1),
      _m(
        '5',
        'bob',
        '↪ [Forwarded by bob • from carol]: Quarterly numbers\nline two',
        0,
      ),
      _m('4', 'ann', '↪ [Forwarded by ann]: no original author', 0),
      _m('12', me, '↪ [Forwarded by $me • from carol]: mine, with author', 0),
      _m('13', me, '↪ [Forwarded by $me]: mine, no original author', 0),
      _m('14', me, 'Ping @me and @ann on my own bubble', 0),
      _m('3', me, 'Edited text for @ann', 0, editedTs: 1),
      _m('2', 'bob', 'Reply to a message that is not loaded', 0, replyTo: '41'),
      _m('1', 'ann', 'This one was deleted', 0, isDeleted: true),
      for (final (i, d) in documents.indexed)
        _m('${20 + i}', i.isEven ? 'ann' : me, d.$1.build(), 0),
    ];
    final now = DateTime.now();
    final out = <ChatItem>[];
    Message? prev;
    for (final m in samples.where((m) => !m.isDeleted)) {
      if (prev == null || !ChatTime.isSameDay(prev.ts, m.ts)) {
        out.add(ChatItem.day(ChatTime.day(m.ts, now)));
      }
      out.add(ChatItem.message(m, showName: !m.isMine));
      prev = m;
    }
    return out;
  }
}
