import 'dart:async';

import 'package:get/get.dart';

import '../../data/models/ids.dart';
import '../../data/models/message.dart';

/// Debug-only sample messages for the conversation screen (SEED_UI=1). In
/// memory only: nothing goes to SQLite, SessionStore or secure storage.
/// A send here walks through pending, sending, sent, delivered and read on
/// timers, so the status marks can be seen without a server.
class SeedMessages {
  SeedMessages._();

  static const me = 'alex';
  static final _lists = <String, RxList<Message>>{};
  static int _next = 5000;

  static RxList<Message> of(String convId) =>
      _lists.putIfAbsent(convId, () => _build(convId).obs);

  static int _minutes(int n) =>
      DateTime.now().millisecondsSinceEpoch - n * 60 * 1000;

  static Message _m(
    String convId,
    int id,
    String sender,
    String text,
    int minutesAgo, {
    MessageStatus? status,
    String? replyTo,
    bool isDeleted = false,
    bool isEncrypted = false,
    String? cid,
  }) {
    final isMine = sender == me;
    return Message(
      msgId: '$id',
      convId: convId,
      sender: sender,
      isMine: isMine,
      text: text,
      ts: _minutes(minutesAgo),
      status: status ?? (isMine ? MessageStatus.read : MessageStatus.sent),
      replyTo: replyTo,
      isDeleted: isDeleted,
      isEncryptedUnsupported: isEncrypted,
      localSeq: id,
      cid: cid,
    );
  }

  static List<Message> _build(String c) {
    switch (c) {
      case 'dm:priya':
        return [
          _m(
            c,
            1001,
            'priya',
            'Hey Alex! The updated workflow is ready for your review. I simplified the approval steps and moved the attachments to the end.',
            1700,
          ),
          _m(c, 1002, me, 'Looks great, Priya. The simpler the better.', 1695),
          _m(c, 1003, 'priya', 'Glad it works for you.', 70),
          _m(
            c,
            1004,
            'priya',
            'Here is the doc: https://connectum.example.com/documents/workflow-review-final-version-with-a-very-long-link-that-must-wrap-safely',
            69,
          ),
          _m(
            c,
            1005,
            'priya',
            'Averyveryverylongwordwithoutanybreaksatallthatshouldwrapsafelyinsidethebubbleandnotoverflow',
            68,
          ),
          _m(
            c,
            1006,
            me,
            'Thanks, reading it now.',
            60,
            status: MessageStatus.read,
          ),
          _m(
            c,
            1007,
            me,
            'Quick question on step three.',
            59,
            status: MessageStatus.read,
            replyTo: '1003',
          ),
          _m(
            c,
            1008,
            'priya',
            'This message was removed.',
            40,
            isDeleted: true,
          ),
          _m(c, 1009, 'priya', 'The new flow looks great. Let us ship it!', 3),
          _m(c, 1010, 'priya', 'Can you confirm by end of day?', 2),
        ];
      case 'dm:arjun':
        return [
          _m(c, 2001, 'arjun', 'Can you take a look at the proposal?', 120),
          _m(
            c,
            2002,
            me,
            'Sure, reading it now.',
            110,
            status: MessageStatus.read,
          ),
          _m(
            c,
            2003,
            me,
            'Looks good to me.',
            100,
            status: MessageStatus.delivered,
          ),
          _m(
            c,
            2004,
            me,
            'I will send comments tomorrow.',
            90,
            status: MessageStatus.sent,
          ),
          Message(
            msgId: 'temp-1',
            convId: c,
            sender: me,
            isMine: true,
            text: 'Waiting for a connection to send this one.',
            ts: _minutes(20),
            status: MessageStatus.pending,
            localSeq: 1,
            cid: 'm-seed-1',
          ),
          Message(
            msgId: 'temp-2',
            convId: c,
            sender: me,
            isMine: true,
            text: 'This message could not be sent.',
            ts: _minutes(10),
            status: MessageStatus.failed,
            failReason: 'not_allowed',
            localSeq: 2,
            cid: 'm-seed-2',
          ),
        ];
      case 'group:Design Collective':
        return [
          _m(
            c,
            3001,
            'meera',
            'Morning all. The component audit is finished.',
            300,
          ),
          _m(c, 3002, 'meera', 'I added notes for each screen.', 299),
          _m(
            c,
            3003,
            'ravi',
            'Nice. I will fix the spacing tokens today.',
            290,
          ),
          _m(
            c,
            3004,
            me,
            'Shared the updated components',
            250,
            status: MessageStatus.sent,
          ),
          _m(c, 3005, 'nina', 'Reviewing now.', 20),
          _m(c, 3006, 'ravi', 'Looks good from my side.', 15),
          _m(c, 3007, 'meera', 'One small thing on the badge colour.', 12),
        ];
      case 'dm:ravi':
        return [
          _m(c, 4001, 'ravi', 'e2e1:AAAA', 300, isEncrypted: true),
          _m(c, 4002, me, 'e2e1:BBBB', 295, isEncrypted: true),
          _m(c, 4003, 'ravi', 'e2e1:CCCC', 290, isEncrypted: true),
        ];
      case 'dm:sana':
        return List.generate(300, (i) {
          final isMine = i % 3 == 0;
          final text = i % 17 == 0
              ? 'A longer sample message to check wrapping and spacing in a long thread, number ${i + 1}. It goes on for a couple of lines so the row heights vary.'
              : 'Sample message ${i + 1}';
          return _m(
            c,
            6000 + i,
            isMine ? me : 'sana',
            text,
            (300 - i) * 8,
            status: isMine ? MessageStatus.read : null,
          );
        });
      case 'group:Product & Engineering':
        return [];
      case 'host:hr':
        return [
          _m(c, 7001, 'hr', 'Your leave request was approved.', 13000),
          _m(c, 7002, 'hr', 'Reminder: update your emergency contact.', 12990),
        ];
      case 'global':
        return [
          _m(c, 8001, 'admin', 'Welcome to Agile Labs', 400000),
          _m(c, 8002, 'meera', 'Good morning everyone.', 90),
          _m(c, 8003, me, 'Good morning.', 85, status: MessageStatus.sent),
        ];
      default:
        return [
          _m(
            c,
            9001,
            c.contains(':') ? c.split(':').last : 'someone',
            'Sample message',
            120,
          ),
        ];
    }
  }

  /// Adds a message of mine and walks it through the send states.
  static void send(String convId, String text, {String? replyTo}) {
    final list = of(convId);
    final id = 'temp-${_next++}';
    final isDm = convId.startsWith('dm:');
    list.add(
      Message(
        msgId: id,
        convId: convId,
        sender: me,
        isMine: true,
        text: text,
        ts: DateTime.now().millisecondsSinceEpoch,
        status: MessageStatus.pending,
        replyTo: replyTo,
        localSeq: _next,
        cid: newCid(),
      ),
    );
    _walk(convId, id, isDm);
  }

  static void retry(String convId, String id) {
    _set(convId, id, (m) => m.copyWith(status: MessageStatus.pending));
    _walk(convId, id, convId.startsWith('dm:'));
  }

  static void _walk(String convId, String id, bool isDm) {
    var current = id;
    void step(int ms, MessageStatus status, {bool isFinal = false}) {
      Timer(Duration(milliseconds: ms), () {
        final serverId = status == MessageStatus.sent ? '${_next++}' : null;
        _set(
          convId,
          current,
          (m) => m.copyWith(status: status, msgId: serverId),
        );
        if (serverId != null) current = serverId;
      });
    }

    step(700, MessageStatus.sending);
    step(1500, MessageStatus.sent);
    if (isDm) {
      step(3000, MessageStatus.delivered);
      step(5000, MessageStatus.read);
    }
  }

  static void delete(String convId, String id) {
    final list = of(convId);
    final i = list.indexWhere((m) => m.msgId == id);
    if (i < 0) return;
    final m = list[i];
    if (m.isLocalTemp || m.status == MessageStatus.failed) {
      list.removeAt(i);
    } else {
      list[i] = m.copyWith(isDeleted: true);
    }
  }

  static void _set(String convId, String id, Message Function(Message) update) {
    final list = of(convId);
    final i = list.indexWhere((m) => m.msgId == id);
    if (i >= 0) list[i] = update(list[i]);
  }

  /// A received message arrives after a pause, to see a live entrance.
  static void incoming(String convId, String from, String text) {
    of(convId).add(
      Message(
        msgId: '${_next++}',
        convId: convId,
        sender: from,
        isMine: false,
        text: text,
        ts: DateTime.now().millisecondsSinceEpoch,
        status: MessageStatus.sent,
        localSeq: _next,
      ),
    );
  }
}
