import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../core/utils/attachment_tag.dart';
import '../db/app_database.dart';
import '../models/ids.dart';
import '../models/message.dart';
import '../models/outbox_entry.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';
import '../e2e/e2e_crypto.dart';
import '../e2e/e2e_models.dart';
import 'e2e_repository.dart';
import 'encryption_policy.dart';

/// How a file for a chat is made: uploaded as it is, or sealed first.
enum AttachMode { plain, encrypted }

enum SendResult { queued, blocked, tooLong, invalid, noSession }

enum DeleteResult { deleted, denied, needsConnection, notSupported, failed }

enum ReactResult { sent, needsConnection, notSupported }

class _History {
  const _History(this.items, this.unknown, {this.hasMore = false, this.next});

  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> unknown;
  final bool hasMore;
  final String? next;
}

class OlderPage {
  const OlderPage({
    required this.count,
    required this.hasMore,
    required this.next,
  });

  final int count;
  final bool hasMore;
  final String? next;
}

class MessageRepository extends GetxService {
  MessageRepository(
    this._db,
    this._session,
    this._socket,
    this._conversations,
    this._policy,
    this._e2e,
  );

  static const _ackTimeout = Duration(seconds: 15);
  static const _maxAttempts = 5;
  static const _maxStaleRetries = 2;
  static const _historyPage = 50;
  static const _maxGapPages = 10;
  static const _maxUnlockPages = 30;
  static const _unlockPause = Duration(seconds: 1);
  static const _cidMemory = Duration(hours: 23);
  static const couldNotConfirm = AppDatabase.couldNotConfirm;

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final ConversationRepository _conversations;
  final EncryptionPolicy _policy;
  final E2eRepository _e2e;

  final _lists = <String, RxList<Message>>{};
  final _historyWaiters = <String, Completer<_History>>{};
  final _deleteWaiters = <String, Completer<DeleteResult>>{};
  final _inFlight = <int, OutboxEntry>{};
  final _ackTimers = <int, Timer>{};

  /// Outbox id -> the `mid` of the envelope last put on the socket for it, so
  /// a stale-devices refusal (which names only a `mid`) finds its send.
  final _sealedMids = <int, String>{};
  final _staleTries = <int, int>{};
  Timer? _wakeTimer;
  Future<void> _queue = Future.value();
  Future<void> _decrypting = Future.value();
  bool _isFlushing = false;
  bool _wantsFlush = false;
  bool _isSyncing = false;
  bool _isUnlocking = false;
  String? _unlockingConv;
  int _lastTemp = 0;

  /// Why the last [sendText] was refused with [SendResult.blocked].
  String lastBlock = '';

  /// The client id of the last [sendText] that was queued.
  String lastCid = '';
  String? _openConversation;
  String? _syncScope;

  String? get _org => _session.orgId;
  String? get _me => _session.userId;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen((e) {
      _queue = _queue
          .then((_) => _socket.isCurrent(e) ? _handle(e) : null)
          .catchError((Object _) {});
    });
    _socket.listenOnline('messages', _onOnline);
    _e2e.unlockRequests.listen((_) => unawaited(_unlockLocked()));
    _e2e.registrations.listen((_) => unawaited(reopenNoDevice()));
    _conversations.receiptsChanged.listen(applyReceipts);
    ever(_socket.connection, (state) {
      if (state != SocketState.online) _onDropped();
    });
    ever(_session.current, (_) {
      // The other organisation's messages go before the new one's first read.
      for (final list in _lists.values) {
        list.clear();
      }
      for (final waiter in _historyWaiters.values) {
        if (!waiter.isCompleted) waiter.completeError(StateError('switched'));
      }
      _historyWaiters.clear();
      _lists.keys.toList().forEach(_reload);
      _scheduleDecrypt();
    });
    _scheduleDecrypt();
  }

  /// Completes when every envelope held so far has been tried, so a read
  /// that follows sees the opened text (the AI transcript needs it).
  Future<void> settleDecrypt() => _decrypting;

  void _scheduleDecrypt() {
    _decrypting = _decrypting
        .then((_) => _decryptPending())
        .catchError((Object _) {});
  }

  /// After "Trust new key": messages of [convId] that were hidden because the
  /// sender's key had changed are opened again against the pins as they are
  /// now. Nothing is shown unless the check passes this time.
  Future<void> reopenKeyChanged(String convId) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    await _db.update(
      "UPDATE messages SET decrypt_state = 'pending', plaintext = NULL "
      "WHERE org_id = ? AND user_id = ? AND conv_id = ? AND decrypt_state = 'cant_decrypt' "
      "AND plaintext = 'key_changed'",
      [org, user, convId],
    );
    _scheduleDecrypt();
  }

  /// After this phone was registered: messages that showed "Encryption is not
  /// ready on this device yet" are opened again.
  Future<void> reopenNoDevice() async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    await _db.update(
      "UPDATE messages SET decrypt_state = 'pending', plaintext = NULL "
      "WHERE org_id = ? AND user_id = ? AND decrypt_state = 'cant_decrypt' "
      "AND plaintext = 'no_device'",
      [org, user],
    );
    _scheduleDecrypt();
  }

  /// After this device stopped being late: the server now serves the earlier
  /// envelopes with this device's boxes, but the saved copies are the old ones.
  /// Fetches history again, one conversation at a time and newest first, only
  /// for conversations that hold locked messages, one page a second, and stops
  /// at the oldest locked message, the end of history, [_maxUnlockPages] pages
  /// or the first failed request (then the mark stays and a later connection
  /// tries again). A changed envelope becomes pending and is opened by
  /// [_decryptPending], so the row and the chat preview update in place.
  Future<void> _unlockLocked() async {
    final org = _org;
    final user = _me;
    if (_isUnlocking || org == null || user == null || !_socket.isOnline) {
      return;
    }
    _isUnlocking = true;
    try {
      const locked = "decrypt_state = 'cant_decrypt'";
      final before = await _lockedCount(org, user);
      final rows = await _db.query(
        'SELECT conv_id, MIN(ts) AS oldest FROM messages WHERE org_id = ? AND user_id = ? '
        'AND $locked GROUP BY conv_id ORDER BY MAX(ts) DESC',
        [org, user],
      );
      var isComplete = true;
      for (final r in rows) {
        if (!await _refetchLocked(idText(r['conv_id']), intOf(r['oldest']))) {
          isComplete = false;
          break;
        }
        await _decrypting;
      }
      await _decrypting;
      if (!isComplete || _org != org || _me != user) return;
      await _e2e.finishUnlock(readable: before - await _lockedCount(org, user));
    } finally {
      _unlockingConv = null;
      _isUnlocking = false;
    }
  }

  Future<int> _lockedCount(String org, String user) async {
    final rows = await _db.query(
      'SELECT COUNT(*) AS n FROM messages WHERE org_id = ? AND user_id = ? '
      "AND decrypt_state = 'cant_decrypt'",
      [org, user],
    );
    return rows.isEmpty ? 0 : intOf(rows.first['n']);
  }

  /// Latest page, then older ones, until the page reaches [oldestTs]. False
  /// when a request failed or the connection went.
  Future<bool> _refetchLocked(String convId, int oldestTs) async {
    _unlockingConv = convId;
    var page = await _fetchHistory(convId);
    for (var n = 0; n < _maxUnlockPages; n++) {
      if (page == null || !_socket.isOnline) return false;
      final stamps = [
        for (final i in page.items)
          if (i['ts'] != null) intOf(i['ts']),
      ];
      final isReached =
          stamps.isNotEmpty && stamps.reduce(math.min) <= oldestTs;
      if (isReached || !page.hasMore || page.next == null) return true;
      await Future<void>.delayed(_unlockPause);
      page = await _fetchHistory(convId, before: page.next);
    }
    return true;
  }

  /// Opens every envelope still marked pending and stores the outcome. A
  /// message that cannot be opened stays unreadable (one directory refresh is
  /// tried inside [E2eRepository.open]); one that could not be tried because
  /// the server was unreachable stays pending until the next connection.
  Future<void> _decryptPending() async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final rows = await _db.query(
      'SELECT msg_id, conv_id, text FROM messages WHERE org_id = ? AND user_id = ? '
      "AND decrypt_state = 'pending'",
      [org, user],
    );
    final touched = <String>{};
    for (final r in rows) {
      final id = idText(r['msg_id']);
      final convId = idText(r['conv_id']);
      final envelope = idText(r['text']);
      final reading = await _e2e.open(text: envelope, convId: convId);
      if (reading.state == E2eReadState.pending) continue;
      final isOk = reading.state == E2eReadState.ok;
      await _db.update(
        'UPDATE messages SET plaintext = ?, decrypt_state = ? WHERE org_id = ? AND user_id = ? '
        'AND msg_id = ? AND text = ?',
        [
          isOk ? reading.text : reading.code,
          isOk ? 'ok' : 'cant_decrypt',
          org,
          user,
          id,
          envelope,
        ],
      );
      if (kDebugMode) {
        debugPrint('e2e: message $id ${isOk ? 'ok' : reading.code}');
      }
      touched.add(convId);
    }
    if (touched.isEmpty) return;
    for (final convId in touched) {
      if (_lists.containsKey(convId)) await _reload(convId);
    }
    await _conversations.reload();
  }

  RxList<Message> messages(String convId) {
    final existing = _lists[convId];
    if (existing != null) return existing;
    final list = <Message>[].obs;
    _lists[convId] = list;
    _reload(convId);
    return list;
  }

  /// The thread on screen. Messages that arrive in it do not count as unread
  /// (the screen reports what it showed through `markRead`).
  /// The thread's cached messages, ready to show: the list is filled from
  /// SQLite before this returns.
  Future<RxList<Message>> open(String convId) async {
    final list = messages(convId);
    await _reload(convId);
    return list;
  }

  /// Latest page of one conversation (and the gap check), when online.
  Future<void> syncConversation(String convId) async {
    if (!_socket.isOnline) return;
    await _syncConversation(convId);
  }

  /// What a send into [convId] would do right now, for the composer. Without
  /// [isLookup] it reads caches only; an unanswered question is `unknown`,
  /// which does not block typing (the send waits and decides when it goes out).
  Future<E2eSendDecision> sendGate(
    String convId, {
    bool isLookup = false,
  }) async => _policy.decideSend(
    convId,
    await _facts(convId),
    isLookup: isLookup && _socket.isOnline,
  );

  /// True when the thread has encrypted history (shown as a lock).
  Future<bool> hasEncryptedHistory(String convId) async =>
      (await _facts(convId)).isE2e;

  /// Deletes one of my messages. A message that never reached the server (still
  /// waiting or failed) is removed here, offline too; a sent one needs the
  /// connection and the server's answer (`/delete` exists for direct messages,
  /// groups and the global room, not for teams).
  Future<DeleteResult> deleteMessage(Message m) async {
    if (m.isLocalTemp || m.status == MessageStatus.failed) {
      await _db.transaction((sql) async {
        await sql.update(
          'DELETE FROM outbox WHERE org_id = ? AND user_id = ? AND ref_id = ?',
          [_org, _me, m.msgId],
        );
        await sql.update(
          'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [_org, _me, m.msgId],
        );
      });
      await _reload(m.convId);
      await _conversations.reload();
      return DeleteResult.deleted;
    }
    final kind = ConversationRepository.kindOf(m.convId);
    final target = ConversationRepository.targetOf(m.convId);
    final command = switch (kind) {
      'dm' => '/delete dm $target ${m.msgId}',
      'group' => '/delete group $target ${m.msgId}',
      'global' => '/delete global ${m.msgId}',
      _ => null,
    };
    if (command == null) return DeleteResult.notSupported;
    if (!_socket.isOnline) return DeleteResult.needsConnection;
    final waiter = Completer<DeleteResult>();
    _deleteWaiters[m.msgId] = waiter;
    try {
      if (!await _socket.sendCommand(command)) {
        return DeleteResult.needsConnection;
      }
      return await waiter.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => DeleteResult.failed,
      );
    } finally {
      _deleteWaiters.remove(m.msgId);
    }
  }

  /// Toggles my reaction on a message. Online only and never queued: the
  /// server toggles, so a repeat would undo it. The answer is the pushed
  /// reaction set (stored by [_onReaction]); nothing is predicted here.
  Future<ReactResult> react(Message m, String emoji) async {
    final target = ConversationRepository.targetOf(m.convId);
    final command = switch (ConversationRepository.kindOf(m.convId)) {
      'dm' => '/react dm $target ${m.msgId} $emoji',
      'group' => '/react group $target ${m.msgId} $emoji',
      'global' => '/react global ${m.msgId} $emoji',
      _ => null,
    };
    if (command == null || numericId(m.msgId) == null) {
      return ReactResult.notSupported;
    }
    if (!await _socket.sendCommand(command)) return ReactResult.needsConnection;
    return ReactResult.sent;
  }

  void setOpenConversation(String? convId) {
    _openConversation = convId;
  }

  Future<void> _reload(String convId) async {
    final org = _org;
    final user = _me;
    final list = _lists[convId];
    if (list == null) return;
    if (org == null || user == null) {
      list.clear();
      return;
    }
    final rows = await readFor(org, user, convId);
    if (org != _org || user != _me) return;
    list.assignAll(rows);
  }

  /// The messages of one thread of one organisation and person, from SQLite.
  Future<List<Message>> readFor(String org, String user, String convId) async {
    final rows = await _db.query(
      'SELECT * FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? '
      "ORDER BY CASE WHEN msg_id LIKE 'temp-%' THEN 1 ELSE 0 END, ts, local_seq",
      [org, user, convId],
    );
    return rows.map(Message.fromRow).toList();
  }

  String _tempId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastTemp = now > _lastTemp ? now : _lastTemp + 1;
    return 'temp-$_lastTemp';
  }

  Future<ThreadFacts> _facts(String convId) async {
    final rows = await _db.query(
      'SELECT is_encrypted, (SELECT COUNT(*) FROM messages m WHERE m.org_id = c.org_id AND m.user_id = c.user_id '
      "AND m.conv_id = c.conv_id AND m.msg_id NOT LIKE 'temp-%') AS n "
      'FROM conversations c WHERE c.org_id = ? AND c.user_id = ? AND c.conv_id = ?',
      [_org, _me, convId],
    );
    if (rows.isEmpty) return const ThreadFacts(isE2e: false, hasHistory: false);
    return ThreadFacts(
      isE2e: intOf(rows.first['is_encrypted']) == 1,
      hasHistory: intOf(rows.first['n']) > 0,
    );
  }

  // ---- composing ----------------------------------------------------------

  static const _noCommands =
      'Messages that start with # are reserved for commands';

  /// A `#command`: blocked in encrypted threads. A leading `@name` is an
  /// ordinary mention and is allowed.
  static bool isCommandLike(String text) =>
      RegExp(r'^#[A-Za-z]').hasMatch(text);

  Future<SendResult> sendText(
    String convId,
    String text, {
    String? replyTo,
  }) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return SendResult.noSession;
    final body = text.trim();
    if (body.isEmpty) return SendResult.invalid;
    if (body.length > 2000) return SendResult.tooLong;
    if (convId == 'global' && body.startsWith('/')) return SendResult.invalid;
    if (replyTo != null && replyTo.startsWith('temp-')) {
      return SendResult.invalid;
    }
    // A send that can never work (no encryption set up by the peer, a changed
    // key, an encrypted group) is refused here; one that may work later is
    // queued and decided again when it goes out.
    final facts = await _facts(convId);
    final gate = await _policy.decideSend(convId, facts, isLookup: false);
    if (gate.isBlocked && !gate.isTransient) {
      lastBlock = gate.message;
      return SendResult.blocked;
    }
    if ((gate.isEncrypt || facts.isE2e) && isCommandLike(body)) {
      lastBlock = _noCommands;
      return SendResult.blocked;
    }
    final isSecure = gate.isEncrypt || facts.isE2e;
    final tempId = _tempId();
    final cid = newCid();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((sql) async {
      await ConversationRepository.ensure(sql, org, user, convId);
      await sql.insert(
        'INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, kind, text, ts, reply_to, status, local_seq, cid, '
        'is_encrypted_unsupported, plaintext, decrypt_state) '
        "VALUES(?,?,?,?,?,1,'chat',?,?,?,'pending',?,?,?,?,?)",
        [
          org,
          user,
          tempId,
          convId,
          user,
          body,
          now,
          replyTo,
          now,
          cid,
          isSecure ? 1 : 0,
          isSecure ? body : null,
          isSecure ? 'ok' : null,
        ],
      );
      await sql.insert(
        'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts, cid) '
        "VALUES(?,?,?,?,?,?,'pending',?,?)",
        [
          org,
          user,
          convId,
          replyTo == null ? 'message' : 'reply',
          jsonEncode({'text': body, 'replyTo': replyTo}),
          tempId,
          now,
          cid,
        ],
      );
      await sql.update(
        'UPDATE conversations SET last_text = ?, last_ts = ?, last_from = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [body, now, user, org, user, convId],
      );
    });
    lastCid = cid;
    await _reload(convId);
    await _conversations.reload();
    unawaited(flush());
    return SendResult.queued;
  }

  static const encryptedAttachmentBlock =
      "A file can't be sent unencrypted in an encrypted chat";
  static const _unconfirmedEncryption =
      "Couldn't confirm this chat's encryption. Try again";

  /// How a file must travel into [convId], asked of the server right before
  /// it is encrypted or uploaded. Null when the send is blocked or cannot be
  /// told yet ([lastBlock] says why); never `plain` for an encrypted thread.
  Future<AttachMode?> attachMode(String convId) async {
    final facts = await _facts(convId);
    final gate = await _policy.decideSend(convId, facts);
    if (gate.isBlocked) {
      lastBlock = gate.message;
      return null;
    }
    if (gate.isEncrypt) return AttachMode.encrypted;
    if (facts.isE2e || gate.verdict == E2eSendVerdict.unknown) {
      lastBlock = _unconfirmedEncryption;
      return null;
    }
    return AttachMode.plain;
  }

  /// Sends the attachment tag as an ordinary message through the same outbox
  /// path as text. The policy decides first, and the tag must match it: a tag
  /// with a key goes only into an encrypted send, one without never does (the
  /// flush checks again, so a file or its key is never sent in plain text).
  Future<SendResult> sendAttachment(
    String convId,
    AttachmentTag tag, {
    String? replyTo,
  }) async {
    final String text;
    try {
      text = tag.build();
    } on FormatException {
      return SendResult.invalid;
    }
    return _sendTagged(convId, text, tag, replyTo: replyTo);
  }

  /// A forward of an attachment: [text] is the forward line and the tag as it
  /// was received, kept byte for byte (the key and iv are in it). The same
  /// policy match as [sendAttachment] applies to the target conversation.
  Future<SendResult> sendForwardedAttachment(
    String convId,
    String text,
    AttachmentTag tag,
  ) => _sendTagged(convId, text, tag);

  Future<SendResult> _sendTagged(
    String convId,
    String text,
    AttachmentTag tag, {
    String? replyTo,
  }) async {
    final facts = await _facts(convId);
    final gate = await _policy.decideSend(convId, facts, isLookup: false);
    if (gate.isBlocked && !gate.isTransient) {
      lastBlock = gate.message;
      return SendResult.blocked;
    }
    final isSecure = gate.isEncrypt || facts.isE2e;
    if (isSecure != tag.isEncrypted) {
      lastBlock = tag.isEncrypted
          ? _unconfirmedEncryption
          : encryptedAttachmentBlock;
      return SendResult.blocked;
    }
    return sendText(convId, text, replyTo: replyTo);
  }

  /// What the policy says about [convId] right now, asking the server when
  /// it has to. Used before a raw `#` line may leave the phone.
  Future<EncryptionVerdict> verdictOf(String convId) async =>
      _policy.verdict(convId, await _facts(convId));

  Future<bool> editText(String msgId, String text) async {
    final org = _org;
    final user = _me;
    final body = text.trim();
    if (org == null || user == null || body.isEmpty || body.length > 2000) {
      return false;
    }
    final rows = await _db.query(
      'SELECT * FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [org, user, msgId],
    );
    if (rows.isEmpty) return false;
    final message = Message.fromRow(rows.first);
    if (!message.isMine || message.isDeleted || message.kind != 'chat') {
      return false;
    }
    if (message.isEncrypted) return false;
    if (message.convId.startsWith('host:')) return false;
    if (message.isLocalTemp) {
      final pending = await _db.query(
        'SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND ref_id = ? '
        "AND status IN ('pending','failed') AND kind IN ('message','reply')",
        [org, user, msgId],
      );
      if (pending.isEmpty) return false;
      final entry = OutboxEntry.fromRow(pending.first);
      await _db.update('UPDATE outbox SET payload_json = ? WHERE id = ?', [
        jsonEncode({...entry.payload, 'text': body}),
        entry.id,
      ]);
      await _db.update(
        'UPDATE messages SET text = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [body, org, user, msgId],
      );
    } else {
      await _db.transaction((sql) async {
        await sql.insert(
          'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts) '
          "VALUES(?,?,?,'edit',?,?,'pending',?)",
          [
            org,
            user,
            message.convId,
            jsonEncode({'text': body, 'prevText': message.text}),
            msgId,
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
        await sql.update(
          'UPDATE messages SET text = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [body, org, user, msgId],
        );
      });
    }
    await _reload(message.convId);
    unawaited(flush());
    return true;
  }

  Future<void> retry(String msgId) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET status = 'pending', retry_count = 0, next_attempt_ts = 0, last_error = NULL, first_attempt_ts = NULL "
        "WHERE org_id = ? AND user_id = ? AND ref_id = ? AND status = 'failed'",
        [org, user, msgId],
      );
      await sql.update(
        "UPDATE messages SET status = 'pending', fail_reason = NULL "
        "WHERE org_id = ? AND user_id = ? AND msg_id = ? AND status = 'failed'",
        [org, user, msgId],
      );
    });
    await _reloadAll();
    unawaited(flush());
  }

  /// Another repository changed message rows (a pending form card): the open
  /// lists and the chat list read them again.
  Future<void> reloadAfterLocalChange() async {
    await _reloadAll();
    await _conversations.reload();
  }

  Future<void> _reloadAll() async {
    for (final id in _lists.keys.toList()) {
      await _reload(id);
    }
  }

  // ---- outbox flusher -----------------------------------------------------

  /// One chat command is in flight per conversation, in outbox order across
  /// conversations. An ack names its message by cid, so a resend after a
  /// drop reuses the cid and the server answers the first ack again.
  Future<void> flush() async {
    if (_isFlushing) {
      _wantsFlush = true;
      return;
    }
    _isFlushing = true;
    try {
      do {
        _wantsFlush = false;
        await _flushPass();
      } while (_wantsFlush);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _flushPass() async {
    while (_socket.isOnline && _session.hasSession) {
      final entry = await _nextPending();
      if (entry == null) {
        await _scheduleWake();
        return;
      }
      if (await _send(entry) == _Outcome.stopped) return;
    }
  }

  /// The oldest due entry whose conversation has nothing in flight and no
  /// earlier entry waiting out a delay.
  Future<OutboxEntry?> _nextPending() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _db.query(
      "SELECT o.* FROM outbox o WHERE o.org_id = ? AND o.user_id = ? AND o.status = 'pending' "
      "AND o.kind IN ('message','reply','edit') AND o.next_attempt_ts <= ? "
      'AND NOT EXISTS (SELECT 1 FROM outbox p WHERE p.org_id = o.org_id AND p.user_id = o.user_id '
      "AND p.conv_id = o.conv_id AND p.kind IN ('message','reply','edit') "
      "AND (p.status = 'sending' OR (p.status = 'pending' AND p.id < o.id AND p.next_attempt_ts > ?))) "
      'ORDER BY o.id LIMIT 1',
      [_org, _me, now, now],
    );
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  Future<void> _scheduleWake() async {
    final rows = await _db.query(
      "SELECT MIN(next_attempt_ts) AS t FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'pending' "
      "AND kind IN ('message','reply','edit') AND next_attempt_ts > ?",
      [_org, _me, DateTime.now().millisecondsSinceEpoch],
    );
    final next = rows.first['t'];
    if (next == null) return;
    _wakeTimer?.cancel();
    final wait = intOf(next) - DateTime.now().millisecondsSinceEpoch;
    _wakeTimer = Timer(Duration(milliseconds: wait + 50), flush);
  }

  /// The server remembers a client id for a day. An entry first sent more
  /// than 23 hours ago may no longer be protected against a double send.
  bool _isPastCidMemory(OutboxEntry e) =>
      e.firstAttemptTs != null &&
      DateTime.now().millisecondsSinceEpoch - e.firstAttemptTs! >
          _cidMemory.inMilliseconds;

  Future<_Outcome> _send(OutboxEntry entry) async {
    if (entry.retryCount >= _maxAttempts) {
      await _fail(entry, 'too many attempts');
      return _Outcome.finished;
    }
    if (entry.usesCid && _isPastCidMemory(entry)) {
      await _fail(entry, couldNotConfirm);
      return _Outcome.finished;
    }
    // The only place chat text is put on the socket. The decision is asked
    // again here, so a key change or a new device after composing is caught.
    final decision = await _policy.decideSend(
      entry.convId,
      await _facts(entry.convId),
    );
    switch (decision.verdict) {
      case E2eSendVerdict.unknown:
        await _defer(entry, const Duration(seconds: 15));
        return _Outcome.deferred;
      case E2eSendVerdict.blocked:
        if (decision.isSetupPending) {
          await _defer(entry, const Duration(seconds: 15));
          return _Outcome.deferred;
        }
        await _fail(entry, '${E2eSendDecision.failTag}${decision.message}');
        return _Outcome.finished;
      case E2eSendVerdict.plain:
      case E2eSendVerdict.encrypt:
        break;
    }
    String? envelope;
    // A file goes out the way it was made: sealed with its key inside an
    // encrypted send, plain in a plain one. Any other pairing would put the
    // file or its key where the server can read them.
    final tag = AttachmentTag.parse('${entry.payload['text']}');
    if (tag != null && tag.isEncrypted != decision.isEncrypt) {
      await _fail(entry, '${E2eSendDecision.failTag}$encryptedAttachmentBlock');
      return _Outcome.finished;
    }
    if (decision.isEncrypt) {
      if (isCommandLike('${entry.payload['text']}')) {
        await _fail(entry, '${E2eSendDecision.failTag}$_noCommands');
        return _Outcome.finished;
      }
      if (entry.kind == 'edit') {
        await _fail(
          entry,
          "${E2eSendDecision.failTag}Editing isn't supported in encrypted chats yet",
        );
        return _Outcome.finished;
      }
      try {
        envelope = await _e2e.seal(
          decision,
          entry.convId,
          '${entry.payload['text']}',
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'e2e: could not encrypt (${e is E2eException ? e.code : e.runtimeType})',
          );
        }
        await _fail(
          entry,
          '${E2eSendDecision.failTag}${E2eSendDecision.cantSend}: encryption failed',
        );
        return _Outcome.finished;
      }
      // Last line of defence: an encrypt verdict never goes out as plain text.
      if (!E2eCrypto.isEnvelope(envelope)) {
        await _fail(
          entry,
          '${E2eSendDecision.failTag}${E2eSendDecision.cantSend}',
        );
        return _Outcome.finished;
      }
    }
    if (envelope != null) {
      final mid = E2eCrypto.midOf(envelope);
      if (mid != null) _sealedMids[entry.id] = mid;
    }
    final command = wireCommand(entry, text: envelope);
    if (command == null) {
      await _fail(entry, 'unsupported in this conversation');
      return _Outcome.finished;
    }
    final cursor = await _cursor(entry.convId);
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET status = 'sending', attempt_ts = ?, first_attempt_ts = COALESCE(first_attempt_ts, ?), "
        'retry_count = retry_count + 1, cursor_at_send = ? WHERE id = ?',
        [now, now, cursor, entry.id],
      );
      if (entry.kind != 'edit') {
        await sql.update(
          "UPDATE messages SET status = 'sending' WHERE org_id = ? AND user_id = ? AND msg_id = ?",
          [_org, _me, entry.refId],
        );
      }
      if (envelope != null) {
        // The row keeps my plaintext and holds the envelope as sent.
        await sql.update(
          "UPDATE messages SET text = ?, plaintext = ?, decrypt_state = 'ok', is_encrypted_unsupported = 1 "
          'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [envelope, '${entry.payload['text']}', _org, _me, entry.refId],
        );
        await sql.update(
          'UPDATE conversations SET is_encrypted = 1 WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [_org, _me, entry.convId],
        );
      }
    });
    _inFlight[entry.id] = OutboxEntry(
      id: entry.id,
      convId: entry.convId,
      kind: entry.kind,
      payload: entry.payload,
      refId: entry.refId,
      status: 'sending',
      retryCount: entry.retryCount + 1,
      nextAttemptTs: entry.nextAttemptTs,
      createdTs: entry.createdTs,
      cursorAtSend: cursor,
      attemptTs: now,
      cid: entry.cid,
      firstAttemptTs: entry.firstAttemptTs ?? now,
    );
    final sent = await _socket.sendCommand(command);
    if (!sent) {
      _inFlight.remove(entry.id);
      await _backToPending(entry, countAttempt: false);
      return _Outcome.stopped;
    }
    _ackTimers[entry.id]?.cancel();
    _ackTimers[entry.id] = Timer(_ackTimeout, () => _onAckTimeout(entry.id));
    await _reload(entry.convId);
    return _Outcome.inFlight;
  }

  /// The line put on the socket. A send to a DM, group or host goes inside
  /// `/c <cid> ...`; the global room cannot take a client id.
  static String? wireCommand(OutboxEntry e, {String? text}) {
    final command = _commandFor(e, text: text);
    if (command == null) return null;
    return e.usesCid ? '/c ${e.cid} $command' : command;
  }

  /// The same line for a debug send, without an outbox entry.
  static String? cidCommand(String convId, String text, String cid) {
    final kind = ConversationRepository.kindOf(convId);
    if (kind != 'dm' && kind != 'group' && kind != 'host') return null;
    final target = ConversationRepository.targetOf(convId);
    final command = switch (kind) {
      'dm' => '/msg $target $text',
      'group' => '/groupmsg $target $text',
      _ => '/hostmsg $target $text',
    };
    return '/c $cid $command';
  }

  static String? _commandFor(OutboxEntry e, {String? text}) {
    text ??= '${e.payload['text']}';
    final reply = e.payload['replyTo'] as String?;
    final kind = ConversationRepository.kindOf(e.convId);
    final target = ConversationRepository.targetOf(e.convId);
    switch (e.kind) {
      case 'message':
        return switch (kind) {
          'dm' => '/msg $target $text',
          'group' => '/groupmsg $target $text',
          'host' => '/hostmsg $target $text',
          _ => text.startsWith('#') ? '#$text' : text,
        };
      case 'reply':
        return switch (kind) {
          'dm' => '/replydm $target $reply $text',
          'group' => '/replygroup $target $reply $text',
          'global' => '/reply $reply $text',
          _ => null,
        };
      case 'edit':
        return switch (kind) {
          'dm' => '/edit dm $target ${e.refId} $text',
          'group' => '/edit group $target ${e.refId} $text',
          'global' => '/edit global ${e.refId} $text',
          _ => null,
        };
    }
    return null;
  }

  Future<String?> _cursor(String convId) async {
    final rows = await _db.query(
      'SELECT last_server_id FROM sync_cursor WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    return rows.isEmpty ? null : rows.first['last_server_id'] as String?;
  }

  Future<void> _defer(OutboxEntry e, Duration wait) => _db
      .update('UPDATE outbox SET next_attempt_ts = ? WHERE id = ?', [
        DateTime.now().add(wait).millisecondsSinceEpoch,
        e.id,
      ])
      .then((_) => _scheduleWake());

  Future<void> _backToPending(OutboxEntry e, {bool countAttempt = true}) async {
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET status = 'pending', next_attempt_ts = 0 ${countAttempt ? '' : ', retry_count = MAX(retry_count - 1, 0)'} WHERE id = ?",
        [e.id],
      );
      if (e.kind != 'edit') {
        await sql.update(
          "UPDATE messages SET status = 'pending' WHERE org_id = ? AND user_id = ? AND msg_id = ?",
          [_org, _me, e.refId],
        );
      }
    });
    await _reload(e.convId);
  }

  void _settle(int outboxId) {
    _sealedMids.remove(outboxId);
    _inFlight.remove(outboxId);
    _ackTimers.remove(outboxId)?.cancel();
  }

  Future<void> _fail(OutboxEntry e, String reason) async {
    _settle(e.id);
    _staleTries.remove(e.id);
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET status = 'failed', last_error = ? WHERE id = ?",
        [reason, e.id],
      );
      if (e.kind == 'edit') {
        await sql.update(
          'UPDATE messages SET text = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          ['${e.payload['prevText']}', _org, _me, e.refId],
        );
      } else {
        await sql.update(
          "UPDATE messages SET status = 'failed', fail_reason = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?",
          [reason, _org, _me, e.refId],
        );
      }
    });
    await _reload(e.convId);
    unawaited(flush());
  }

  void _onDropped() {
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    _ackTimers.clear();
    _sealedMids.clear();
    _inFlight.clear();
    for (final waiter in _historyWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('dropped'));
    }
  }

  Future<void> _onAckTimeout(int outboxId) async {
    final entry = _inFlight[outboxId];
    if (entry == null || !_socket.isOnline) return;
    _settle(outboxId);
    await _recover(entry, countAttempt: true);
    unawaited(flush());
  }

  // ---- reconnect and recovery ---------------------------------------------

  Future<void> _onOnline() async {
    _policy.onReconnected();
    _scheduleDecrypt();
    final scope = '$_org/$_me';
    if (_isSyncing && _syncScope == scope) return;
    _isSyncing = true;
    _syncScope = scope;
    try {
      final stale = await _db.query(
        "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'sending' AND kind IN ('message','reply','edit') ORDER BY id",
        [_org, _me],
      );
      for (final row in stale) {
        await _recover(OutboxEntry.fromRow(row), countAttempt: false);
      }
      await flush();
      await _syncAll();
      await flush();
    } finally {
      if (_syncScope == scope) _isSyncing = false;
    }
  }

  Future<void> syncNow() => _onOnline();

  /// An entry that was sent and never acked. A send with a client id is simply
  /// sent again under the same id (the server answers the first ack again),
  /// unless the server's one-day memory of the id may have expired. A global
  /// message cannot carry an id and is checked against history first.
  Future<void> _recover(OutboxEntry entry, {required bool countAttempt}) async {
    _settle(entry.id);
    if (entry.kind == 'edit') {
      await _backToPending(entry, countAttempt: countAttempt);
    } else if (!entry.usesCid) {
      await _reconcileByText(entry);
    } else if (_isPastCidMemory(entry)) {
      await _fail(entry, couldNotConfirm);
    } else {
      await _backToPending(entry, countAttempt: countAttempt);
    }
  }

  Future<void> _syncAll() async {
    final org = _org;
    final user = _me;
    if (org == null || user == null || !_socket.isOnline) return;
    await _conversations.requestLists();
    if (_org != org || _me != user) return;
    await _db.transaction(
      (sql) => ConversationRepository.ensure(sql, org, user, 'global'),
    );
    final rows = await _db.query(
      'SELECT conv_id FROM conversations WHERE org_id = ? AND user_id = ? AND is_archived = 0',
      [org, user],
    );
    for (final row in rows) {
      if (!_socket.isOnline || _org != org || _me != user) return;
      await _syncConversation(idText(row['conv_id']));
    }
    await _conversations.reload();
  }

  /// Fetches the latest page. When my last known server id is not in it,
  /// pages backwards with `before` until it is, the history ends, or the cap
  /// of pages is reached (then the conversation is flagged as having a gap).
  /// The id is looked for in the page; ids are never compared as numbers.
  Future<void> _syncConversation(String convId) async {
    final org = _org;
    final user = _me;
    final lastKnown = await _cursor(convId);
    final latest = await _fetchHistory(convId);
    if (_org != org || _me != user) return;
    if (latest == null || lastKnown == null || latest.items.isEmpty) return;
    if (_holds(latest, lastKnown)) return;
    var before = idText(latest.items.first['id']);
    for (var page = 0; page < _maxGapPages; page++) {
      if (_org != org || _me != user) return;
      if (!_socket.isOnline) break;
      final older = await _fetchHistory(convId, before: before);
      if (older == null) break;
      if (_holds(older, lastKnown) || !older.hasMore || older.next == null) {
        return;
      }
      before = older.next!;
    }
    await _db.update(
      'UPDATE sync_cursor SET gap_to = COALESCE(gap_to, ?) WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [lastKnown, _org, _me, convId],
    );
  }

  bool _holds(_History page, String id) =>
      page.items.any((i) => idText(i['id']) == id);

  Future<_History?> _fetchHistory(String convId, {String? before}) async {
    final key = before == null ? convId : 'older:$convId';
    final existing = _historyWaiters[key];
    if (existing != null) {
      return existing.future
          .then<_History?>((h) => h)
          .catchError((Object _) => null);
    }
    final kind = ConversationRepository.kindOf(convId);
    final target = ConversationRepository.targetOf(convId);
    final waiter = Completer<_History>();
    _historyWaiters[key] = waiter;
    try {
      final scope = kind == 'global' ? 'global' : '$kind $target';
      final sent = await _socket.sendCommand(
        before == null ? '/history $scope' : '/history $scope before $before',
      );
      if (!sent) return null;
      return await waiter.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    } finally {
      if (identical(_historyWaiters[key], waiter)) _historyWaiters.remove(key);
    }
  }

  /// Pulls the newest pages of [convId] from the server into SQLite until
  /// about [atLeast] messages arrived, the history ends, or [maxPages] pages
  /// were read (50 messages a page). Returns whether older messages remain,
  /// or null when offline or a page did not arrive. Nothing but the normal
  /// history handling writes the rows.
  Future<bool?> fetchRecent(
    String convId, {
    required int atLeast,
    int maxPages = 10,
  }) async {
    if (_org == null || _me == null || !_socket.isOnline) return null;
    var page = await _fetchHistory(convId);
    if (page == null) return null;
    var got = page.items.length;
    // The newest page does not say `hasMore`: a full page means there may be
    // older ones, and the oldest id of the page is where to go on from.
    var more = page.items.length >= _historyPage;
    String? before = more && page.items.isNotEmpty
        ? idText(page.items.first['id'])
        : null;
    for (var pages = 1; more && got < atLeast && pages < maxPages; pages++) {
      if (before == null || before.isEmpty) break;
      final older = await _fetchHistory(convId, before: before);
      if (older == null) return null;
      got += older.items.length;
      more = older.hasMore;
      before = older.next;
    }
    return more;
  }

  /// Loads the page of messages older than the oldest one held (or than the
  /// `next` the server gave last time, which also moves past a page that
  /// showed nothing). Null when offline, nothing is stored yet, or no answer.
  Future<OlderPage?> loadOlder(String convId) async {
    if (_org == null || _me == null || !_socket.isOnline) return null;
    final before = await _olderBoundary(convId);
    if (before == null) return null;
    final page = await _fetchHistory(convId, before: before);
    if (page == null) return null;
    final gap = await _db.query(
      'SELECT gap_to FROM sync_cursor WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    final gapTo = gap.isEmpty ? null : gap.first['gap_to'] as String?;
    if (gapTo != null && (_holds(page, gapTo) || !page.hasMore)) {
      await _db.update(
        'UPDATE sync_cursor SET gap_to = NULL WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [_org, _me, convId],
      );
    }
    return OlderPage(
      count: page.items.length,
      hasMore: page.hasMore,
      next: page.next,
    );
  }

  Future<String?> _olderBoundary(String convId) async {
    final saved = await _db.query(
      'SELECT next_id FROM sync_cursor WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    final next = saved.isEmpty ? null : saved.first['next_id'] as String?;
    if (next != null && next.isNotEmpty) return next;
    final oldest = await _db.query(
      'SELECT msg_id FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? '
      "AND msg_id NOT LIKE 'temp-%' ORDER BY ts, LENGTH(msg_id), msg_id LIMIT 1",
      [_org, _me, convId],
    );
    return oldest.isEmpty ? null : idText(oldest.first['msg_id']);
  }

  /// Whether older messages are known to exist (`hasMore`), and whether a gap
  /// after a reconnect is still open.
  Future<({bool? hasMore, bool hasGap})> olderState(String convId) async {
    final rows = await _db.query(
      'SELECT has_more, gap_to FROM sync_cursor WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    if (rows.isEmpty) return (hasMore: null, hasGap: false);
    final more = rows.first['has_more'];
    return (
      hasMore: more == null ? null : intOf(more) == 1,
      hasGap: rows.first['gap_to'] != null,
    );
  }

  /// Duplicate protection for a global-room message, which cannot carry a
  /// client id: after a drop or an ack timeout the history is fetched and
  /// searched before anything is re-sent.
  ///
  /// Match: a message in the fetched history that is from me, kind `chat`,
  /// has exactly the same text (and replyTo), has a server id above
  /// `cursor_at_send` and was not already held locally before the merge.
  /// Found -> adopt its id as the ack. Not found -> re-send only if the
  /// history clearly reaches back past the cursor (fewer than 50 items, so it
  /// is the whole thread, or it holds an id <= the cursor). Otherwise, or if
  /// the history cannot be fetched while online, the message is failed with
  /// "couldn't confirm delivery" and never auto-resent.
  Future<void> _reconcileByText(OutboxEntry entry) async {
    final history = await _fetchHistory(entry.convId);
    if (history == null) {
      if (!_socket.isOnline) return;
      await _fail(entry, couldNotConfirm);
      return;
    }
    final cursor = idNumber(entry.cursorAtSend);
    final me = (_me ?? '').toLowerCase();
    final text = '${entry.payload['text']}';
    final reply = idText(entry.payload['replyTo']);
    Map<String, dynamic>? match;
    for (final item in history.unknown) {
      final id = idNumber(item['id']);
      if (idText(item['from']).toLowerCase() == me &&
          (item['kind'] ?? 'chat') == 'chat' &&
          idText(item['text']) == text &&
          idText(item['replyTo']) == reply &&
          (cursor == null || (id != null && id > cursor))) {
        if (match == null || (id ?? 0) < (idNumber(match['id']) ?? 0)) {
          match = item;
        }
      }
    }
    if (match != null) {
      await _adopt(entry, idText(match['id']), intOf(match['ts']));
      return;
    }
    final ids = history.items.map((i) => idNumber(i['id'])).whereType<int>();
    final reachesBack = entry.cursorAtSend == null
        ? history.items.length < _historyPage
        : cursor != null &&
              (history.items.length < _historyPage ||
                  ids.any((id) => id <= cursor));
    if (reachesBack) {
      await _backToPending(entry);
    } else {
      await _fail(entry, couldNotConfirm);
    }
  }

  // ---- events ---------------------------------------------------------------

  Future<void> _handle(Map<String, dynamic> e) async {
    switch (e['type']) {
      case 'dm_ack':
        await _ack(
          'dm:${idText(e['with']).toLowerCase()}',
          e,
          delivered: e['status'] == 'delivered',
        );
      case 'group_msg_ack':
        await _ack('group:${idText(e['group'])}', e);
      case 'host_ack':
        await _ack('host:${idText(e['host'])}', e);
      case 'own_message_id':
        await _ack('global', e);
      case 'private':
        await _incoming('dm:${idText(e['from']).toLowerCase()}', e);
      case 'group_message':
        await _incoming('group:${idText(e['group'])}', e);
      case 'host_message':
        await _incoming('host:${idText(e['host'])}', e);
      case 'chat':
        await _incoming('global', e);
      case 'dm_read':
        await _onRead(idText(e['from']).toLowerCase());
      case 'history':
        await _onHistory(e);
      case 'error':
        await _onError(e);
      case 'edited':
      case 'dm_edited':
      case 'group_edited':
        await _onEdited(e);
      case 'delete_denied':
        final waiter = _deleteWaiters[idText(e['messageId'])];
        if (waiter != null && !waiter.isCompleted) {
          waiter.complete(DeleteResult.denied);
        }
      case 'edit_denied':
        await _onEditDenied(e);
      case 'deleted':
      case 'dm_deleted':
      case 'group_deleted':
        await _setDeleted(idText(e['messageId']));
      case 'reaction':
      case 'dm_reaction':
      case 'group_reaction':
        await _onReaction(e);
      case 'sd_event':
        final event = e['event'];
        if (event == 'receipt') {
          await _onReceipt((e['data'] as Map?)?.cast<String, dynamic>() ?? {});
        }
        if (event == 'form_message' || event == 'form_message_updated') {
          await _onFormMessage(
            (e['data'] as Map?)?.cast<String, dynamic>() ?? {},
          );
        }
    }
  }

  /// An ack with a `cid` is matched to its outbox row by that id, whether the
  /// ack is the first or a repeated one (`duplicate: true`): both swap the
  /// temp id for the server id and neither creates a second row. An ack
  /// without a cid can only be the global room's.
  Future<void> _ack(
    String convId,
    Map<String, dynamic> e, {
    bool delivered = false,
  }) async {
    final cid = e['cid'];
    OutboxEntry? entry;
    if (cid is String && cid.isNotEmpty) {
      final rows = await _db.query(
        'SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND cid = ? '
        "AND kind IN ('message','reply') AND status IN ('sending','pending') ORDER BY id LIMIT 1",
        [_org, _me, cid],
      );
      if (rows.isNotEmpty) entry = OutboxEntry.fromRow(rows.first);
    } else {
      for (final inFlight in _inFlight.values) {
        if (inFlight.isSend &&
            !inFlight.usesCid &&
            inFlight.convId.toLowerCase() == convId.toLowerCase()) {
          entry = inFlight;
          break;
        }
      }
    }
    if (entry == null) return;
    await _adopt(
      entry,
      idText(e['id']),
      intOf(e['ts']),
      delivered: delivered,
      moveCursor: e['duplicate'] != true,
    );
    unawaited(flush());
  }

  Future<void> _adopt(
    OutboxEntry entry,
    String serverId,
    int ts, {
    bool delivered = false,
    bool moveCursor = true,
  }) async {
    _settle(entry.id);
    _staleTries.remove(entry.id);
    final status = delivered && entry.convId.startsWith('dm:')
        ? MessageStatus.delivered.name
        : MessageStatus.sent.name;
    await _db.transaction((sql) async {
      final exists = await sql.query(
        'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [_org, _me, serverId],
      );
      if (exists.isNotEmpty) {
        final temp = await sql.query(
          'SELECT plaintext, decrypt_state FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [_org, _me, entry.refId],
        );
        await sql.update(
          'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [_org, _me, entry.refId],
        );
        if (temp.isNotEmpty &&
            temp.first['decrypt_state'] == 'ok' &&
            temp.first['plaintext'] != null) {
          await sql.update(
            "UPDATE messages SET plaintext = ?, decrypt_state = 'ok', is_encrypted_unsupported = 1 "
            'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
            [temp.first['plaintext'], _org, _me, serverId],
          );
        }
        await sql.update(
          "UPDATE messages SET is_mine = 1, cid = COALESCE(cid, ?), status = CASE WHEN status IN ('delivered','read') THEN status ELSE ? END WHERE org_id = ? AND user_id = ? AND msg_id = ?",
          [entry.cid, status, _org, _me, serverId],
        );
      } else {
        await sql.update(
          'UPDATE messages SET msg_id = ?, ts = ?, status = ?, fail_reason = NULL, local_seq = 0 '
          'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [serverId, ts, status, _org, _me, entry.refId],
        );
      }
      await sql.update('DELETE FROM outbox WHERE id = ?', [entry.id]);
      if (moveCursor) await _setCursor(sql, entry.convId, serverId);
    });
    await _reload(entry.convId);
    await _conversations.reload();
  }

  /// The newest server id seen for the conversation, taken in arrival order
  /// (never by comparing ids), plus the server time of the last history.
  Future<void> _setCursor(
    Sql sql,
    String convId,
    String? serverId, {
    int? now,
  }) async {
    final id = serverId == null || serverId.isEmpty ? null : serverId;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rows = await sql.query(
      'SELECT 1 FROM sync_cursor WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    if (rows.isEmpty) {
      await sql.insert(
        'INSERT INTO sync_cursor(org_id, user_id, conv_id, last_server_id, last_history_now, synced_ts) VALUES(?,?,?,?,?,?)',
        [_org, _me, convId, id, now, stamp],
      );
    } else {
      await sql.update(
        'UPDATE sync_cursor SET last_server_id = COALESCE(?, last_server_id), last_history_now = COALESCE(?, last_history_now), synced_ts = ? '
        'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [id, now, stamp, _org, _me, convId],
      );
    }
  }

  static const _e2eErrors = {
    'e2e_required',
    'e2e_peer_not_ready',
    'e2e_disabled',
    'e2e_unsupported',
    'bad_envelope',
    'too_long',
  };

  /// The server refused a send on end-to-end grounds. The error names no
  /// message and the server answers lines in order, so it belongs to the
  /// oldest send in flight. The cached device lists and mode are dropped so
  /// a retry asks again.
  Future<void> _onE2eError(String code, {String text = ''}) async {
    final sends = _inFlight.values.where((i) => i.isSend).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    _policy.onReconnected();
    if (sends.isEmpty) return;
    final entry = sends.first;
    final peer = ConversationRepository.targetOf(entry.convId);
    final isGroup = entry.convId.startsWith('group:');
    if (entry.convId.startsWith('dm:')) _e2e.invalidate([peer, _me ?? '']);
    if (isGroup) _e2e.invalidateGroup(peer);
    final why = switch (code) {
      'e2e_peer_not_ready' when isGroup => _notReadyNames(text),
      'e2e_peer_not_ready' => "$peer hasn't set up encryption yet",
      'e2e_disabled' => 'Encryption is switched off for this organisation',
      'too_long' => 'That message is too large to send securely',
      _ =>
        "${E2eSendDecision.cantSend}: the server didn't accept the encrypted message",
    };
    if (kDebugMode) debugPrint('e2e: send refused ($code)');
    await _fail(entry, '${E2eSendDecision.failTag}$why');
  }

  /// `e2e_stale_devices`: somebody's devices changed while the envelope was
  /// being written, and nothing was stored. The refusal names its message by
  /// `mid`, so the send is found exactly (no "oldest in flight" guess). The
  /// row goes back to pending without counting the attempt; the next
  /// [_send] asks `e2e.devices` again and seals a NEW envelope (new `mid`,
  /// same text) under the SAME `cid`. The server does not remember a refused
  /// send, so the same cid is accepted and a repeat is still answered as
  /// `duplicate:true`. At most [_maxStaleRetries] silent tries, then the
  /// message fails (never a loop, never plain text). It does not depend on
  /// the conversation kind: the lookup is made by [_send] through the policy.
  Future<void> _onStaleDevices(Map<String, dynamic> e) async {
    final mid = idText(e['mid']);
    final conv = idText(e['conv']).toLowerCase();
    int? outboxId;
    for (final item in _sealedMids.entries) {
      final entry = _inFlight[item.key];
      if (item.value == mid &&
          entry != null &&
          (conv.isEmpty || entry.convId.toLowerCase() == conv)) {
        outboxId = item.key;
      }
    }
    final entry = outboxId == null ? null : _inFlight[outboxId];
    if (entry == null) {
      if (kDebugMode) debugPrint('e2e: stale refusal for an unknown mid');
      return;
    }
    if (entry.convId.startsWith('group:')) {
      _e2e.invalidateGroup(ConversationRepository.targetOf(entry.convId));
    }
    final users = e['users'];
    _e2e.invalidate([if (users is List) ...users.map((u) => '$u'), _me ?? '']);
    final tries = (_staleTries[entry.id] ?? 0) + 1;
    if (tries > _maxStaleRetries) {
      if (kDebugMode) debugPrint('e2e: stale devices, giving up');
      await _fail(entry, E2eSendDecision.staleFailure);
      return;
    }
    _staleTries[entry.id] = tries;
    if (kDebugMode) debugPrint('e2e: stale devices, resend $tries');
    _settle(entry.id);
    await _backToPending(entry, countAttempt: false);
    unawaited(flush());
  }

  /// "These people have not set up secure messaging yet: a, b." -> "a, b
  /// haven't set up encryption yet"; the group's own words when it differs.
  static String _notReadyNames(String text) {
    final i = text.indexOf(': ');
    final names = i < 0
        ? ''
        : text.substring(i + 2).replaceAll(RegExp(r'\.$'), '');
    if (names.isEmpty) return "some members haven't set up encryption yet";
    return '$names ${names.contains(',') ? "haven't" : "hasn't"} set up encryption yet';
  }

  Future<void> _onError(Map<String, dynamic> e) async {
    final code = idText(e['code']);
    if (code == 'e2e_stale_devices') {
      await _onStaleDevices(e);
      return;
    }
    if (_e2eErrors.contains(code)) {
      await _onE2eError(code, text: idText(e['text']));
      return;
    }
    if (code == 'bad_cid' || code == 'cid_unsupported') {
      final sends = _inFlight.values.where((i) => i.usesCid).toList();
      if (sends.length == 1) {
        await _fail(sends.first, 'client id refused: $code');
      }
      return;
    }
    final conv = e['conv'];
    if (conv == null) return;
    for (final entry in _inFlight.values.toList()) {
      if (entry.isChat &&
          entry.convId.toLowerCase() == idText(conv).toLowerCase()) {
        await _fail(entry, idText(e['code'] ?? e['text']));
        return;
      }
    }
  }

  /// The other person of a direct conversation received or read up to an id
  /// (a live `receipt`). The positions only move forward.
  Future<void> _onReceipt(Map<String, dynamic> data) async {
    final convId = idText(data['conversation']).toLowerCase();
    final upTo = idText(data['upTo']);
    if (!convId.startsWith('dm:') || numericId(upTo) == null) return;
    final isRead = data['kind'] == 'read';
    final rows = await _db.query(
      'SELECT peer_read_id, peer_delivered_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    if (rows.isEmpty) return;
    String next(Object? old) =>
        old != null && !isNewerId(upTo, idText(old)) && numericId(old) != null
        ? idText(old)
        : upTo;
    await _db.update(
      'UPDATE conversations SET peer_read_id = ?, peer_delivered_id = ? '
      'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [
        isRead ? next(rows.first['peer_read_id']) : rows.first['peer_read_id'],
        next(rows.first['peer_delivered_id']),
        _org,
        _me,
        convId,
      ],
    );
    await _applyReceipts(convId);
    await _conversations.reload();
  }

  /// Debug: feeds a receipt as if the server had pushed it, then lists the
  /// status of my numbered messages in that conversation.
  Future<String> debugReceipt(String convId, String kind, String upTo) async {
    await _onReceipt({'conversation': convId, 'kind': kind, 'upTo': upTo});
    final rows = await _db.query(
      "SELECT msg_id, status FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? AND is_mine = 1 ORDER BY ts, local_seq",
      [_org, _me, convId],
    );
    return rows.map((r) => '${r['msg_id']}:${r['status']}').join('  ');
  }

  /// Debug: feeds live messages from another person (a repeat of one id, an
  /// older id and newer ones) and reports the unread count before and after.
  Future<String> debugIncoming(String convId, List<String> ids) async {
    Future<int> unread() async {
      final rows = await _db.query(
        'SELECT unread FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [_org, _me, convId],
      );
      return rows.isEmpty ? -1 : intOf(rows.first['unread']);
    }

    final before = await unread();
    final peer = convId.startsWith('dm:') ? convId.substring(3) : 'someone';
    for (final id in ids) {
      await _incoming(convId, {
        'id': id,
        'from': peer,
        'text': 'debug $id',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
    return 'unread $before -> ${await unread()} after ids ${ids.join(', ')}';
  }

  Future<void> applyReceipts(String convId) async {
    await _applyReceipts(convId);
    await _conversations.reload();
  }

  /// A message of mine in a direct conversation is read when its id is at or
  /// below the other person's read position, delivered when at or below the
  /// delivered one. Ids are stored as text; only an all-digit id takes part,
  /// and a tick only ever moves forward.
  Future<void> _applyReceipts(String convId) async {
    if (!convId.startsWith('dm:') || _org == null || _me == null) return;
    final rows = await _db.query(
      'SELECT peer_read_id, peer_delivered_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    if (rows.isEmpty) return;
    final read = numericId(rows.first['peer_read_id']);
    final delivered = numericId(rows.first['peer_delivered_id']);
    const digits = "msg_id != '' AND msg_id NOT GLOB '*[^0-9]*'";
    if (delivered != null) {
      await _db.update(
        "UPDATE messages SET status = 'delivered' WHERE org_id = ? AND user_id = ? AND conv_id = ? "
        "AND is_mine = 1 AND status = 'sent' AND $digits AND CAST(msg_id AS INTEGER) <= ?",
        [_org, _me, convId, delivered],
      );
    }
    if (read != null) {
      await _db.update(
        "UPDATE messages SET status = 'read' WHERE org_id = ? AND user_id = ? AND conv_id = ? "
        "AND is_mine = 1 AND status IN ('sent','delivered') AND $digits AND CAST(msg_id AS INTEGER) <= ?",
        [_org, _me, convId, read],
      );
    }
    await _reload(convId);
  }

  Future<void> _onRead(String peer) async {
    await _db.update(
      'UPDATE messages SET status = ? WHERE org_id = ? AND user_id = ? AND conv_id = ? '
      "AND is_mine = 1 AND status IN ('sent','delivered')",
      [MessageStatus.read.name, _org, _me, 'dm:$peer'],
    );
    await _reload('dm:$peer');
  }

  Future<void> _onEdited(Map<String, dynamic> e) async {
    final id = idText(e['messageId']);
    await _db.update(
      'UPDATE messages SET text = ?, edited_ts = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [idText(e['text']), intOf(e['editedTs']), _org, _me, id],
    );
    for (final entry in _inFlight.values.toList()) {
      if (entry.kind == 'edit' && entry.refId == id) {
        _settle(entry.id);
        await _db.update('DELETE FROM outbox WHERE id = ?', [entry.id]);
        unawaited(flush());
      }
    }
    await _reloadAll();
  }

  Future<void> _onEditDenied(Map<String, dynamic> e) async {
    for (final entry in _inFlight.values.toList()) {
      if (entry.kind == 'edit' && entry.refId == idText(e['messageId'])) {
        await _fail(entry, 'edit denied: ${idText(e['reason'])}');
        return;
      }
    }
  }

  Future<void> _setDeleted(String id) async {
    final waiter = _deleteWaiters[id];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(DeleteResult.deleted);
    }
    await _db.update(
      'UPDATE messages SET is_deleted = 1 WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [_org, _me, id],
    );
    await _reloadAll();
  }

  Future<void> _onReaction(Map<String, dynamic> e) async {
    if (kDebugMode) debugPrint('REACT event: ${jsonEncode(e)}');
    await _db.update(
      'UPDATE messages SET reactions_json = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [jsonEncode(e['reactions'] ?? []), _org, _me, idText(e['messageId'])],
    );
    await _reloadAll();
  }

  Future<void> _incoming(String convId, Map<String, dynamic> e) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final id = idText(e['id']);
    if (id.isEmpty) return;
    await _db.transaction((sql) async {
      await ConversationRepository.ensure(sql, org, user, convId);
      final isNew = await _upsert(sql, convId, e);
      await _noteIncoming(
        sql,
        convId,
        id: id,
        isNew: isNew,
        isMine: idText(e['from']).toLowerCase() == user.toLowerCase(),
      );
      await _setCursor(sql, convId, id);
    });
    if (idText(e['from']).toLowerCase() != user.toLowerCase()) {
      unawaited(_conversations.noteDelivered(convId, id));
    }
    await _reload(convId);
    await _conversations.reload();
  }

  Future<void> _onFormMessage(Map<String, dynamic> data) async {
    final org = _org;
    final user = _me;
    final convId = idText(data['conversation']);
    if (org == null || user == null || convId.isEmpty) return;
    await _db.transaction((sql) async {
      await ConversationRepository.ensure(sql, org, user, convId);
      final isNew = await _upsert(sql, convId, data, kind: 'form');
      await _dropWaitingCard(sql, convId, data);
      await _noteIncoming(
        sql,
        convId,
        id: idText(data['id']),
        isNew: isNew,
        isMine: idText(data['from']).toLowerCase() == user.toLowerCase(),
      );
      await _setCursor(sql, convId, idText(data['id']));
    });
    await _applyReceipts(convId);
    await _reload(convId);
    await _conversations.reload();
  }

  /// A submission that waited for approval kept a local card; the real form
  /// message has now been posted, so the local one goes.
  Future<void> _dropWaitingCard(
    Sql sql,
    String convId,
    Map<String, dynamic> data,
  ) async {
    final form = data['form'];
    if (form is! Map) return;
    final id = idText(form['submissionId']);
    if (id.isEmpty) return;
    final waiting = await sql.query(
      "SELECT msg_id, form_json FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? AND kind = 'form' "
      "AND msg_id LIKE 'temp-%' AND status = 'sent'",
      [_org, _me, convId],
    );
    for (final w in waiting) {
      try {
        final f = jsonDecode(idText(w['form_json']));
        if (f is Map && idText(f['submissionId']) == id) {
          await sql.update(
            'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
            [_org, _me, w['msg_id']],
          );
        }
      } on FormatException {
        continue;
      }
    }
  }

  Future<void> _onHistory(Map<String, dynamic> e) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final scope = idText(e['scope']);
    final convId = switch (scope) {
      'global' => 'global',
      'dm' => 'dm:${idText(e['with']).toLowerCase()}',
      'group' => 'group:${idText(e['group'])}',
      'host' => 'host:${idText(e['host'])}',
      _ => '',
    };
    if (convId.isEmpty) return;
    final isOlder = e['before'] != null;
    final hasMore = e['hasMore'] == true;
    final next = e['next'] == null ? null : idText(e['next']);
    final items = ((e['list'] as List?) ?? [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final unknown = <Map<String, dynamic>>[];
    final fresh = <int>[];
    await _db.transaction((sql) async {
      await ConversationRepository.ensure(sql, org, user, convId);
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final isNew = await _upsert(
          sql,
          convId,
          item,
          kind: idText(item['kind']).isEmpty ? 'chat' : idText(item['kind']),
          isFromHistory: true,
        );
        if (isNew) unknown.add(item);
        if (isNew && idText(item['from']).toLowerCase() != user.toLowerCase()) {
          fresh.add(i);
        }
      }
      if (isOlder) {
        // Fetching locked messages again must not move the "load older" spot.
        if (convId != _unlockingConv) {
          await _setCursor(sql, convId, null);
          await sql.update(
            'UPDATE sync_cursor SET has_more = ?, next_id = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
            [hasMore ? 1 : 0, next, org, user, convId],
          );
        }
      } else {
        await _countHistory(sql, convId, items, fresh);
        await _setCursor(
          sql,
          convId,
          items.isEmpty ? null : idText(items.last['id']),
          now: intOf(e['now']),
        );
        await sql.update(
          'UPDATE sync_cursor SET has_more = ?, next_id = ? '
          'WHERE org_id = ? AND user_id = ? AND conv_id = ? AND has_more IS NULL',
          [
            items.length >= _historyPage ? 1 : 0,
            items.isEmpty ? null : idText(items.first['id']),
            org,
            user,
            convId,
          ],
        );
      }
    });
    if (!isOlder) {
      final fromOthers = [
        for (final i in items)
          if (idText(i['from']).toLowerCase() != user.toLowerCase())
            idText(i['id']),
      ];
      if (fromOthers.isNotEmpty) {
        unawaited(_conversations.noteDelivered(convId, fromOthers.last));
      }
    }
    await _applyReceipts(convId);
    await _reload(convId);
    await _conversations.reload();
    final waiter = _historyWaiters[isOlder ? 'older:$convId' : convId];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(_History(items, unknown, hasMore: hasMore, next: next));
    }
  }

  // ---- unread ---------------------------------------------------------------
  // The server's number is the source after each sync (`conv.list`). Between
  // syncs a message from someone else counts once when its id is newer than
  // the newest id known for the thread; that id then moves up, so the same
  // message is not counted again when it comes back through history or a
  // sync. A thread with no known newest id yet is not counted from history
  // (it would count everything), only from a live message.

  Future<void> _noteIncoming(
    Sql sql,
    String convId, {
    required String id,
    required bool isNew,
    required bool isMine,
  }) async {
    if (!isNew || isMine || _openConversation == convId) return;
    await _countOther(sql, convId, [id], isLive: true);
  }

  Future<void> _countOther(
    Sql sql,
    String convId,
    List<String> ids, {
    required bool isLive,
  }) async {
    final rows = await sql.query(
      'SELECT last_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    if (rows.isEmpty) return;
    var last = rows.first['last_id'] == null
        ? null
        : idText(rows.first['last_id']);
    var count = 0;
    for (final id in ids) {
      if (last == null) {
        last = id;
        if (isLive) count++;
      } else if (isNewerId(id, last)) {
        last = id;
        count++;
      } else if (numericId(id) == null || numericId(last) == null) {
        if (isLive) count++;
      }
    }
    await sql.update(
      'UPDATE conversations SET unread = unread + ?, last_id = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [count, last, _org, _me, convId],
    );
  }

  /// The latest history page (oldest first): the new messages from others.
  Future<void> _countHistory(
    Sql sql,
    String convId,
    List<Map<String, dynamic>> items,
    List<int> fresh,
  ) async {
    final ids = [for (final i in fresh) idText(items[i]['id'])];
    if (ids.isEmpty || _openConversation == convId) return;
    await _countOther(sql, convId, ids, isLive: false);
  }

  /// Inserts or updates one server message. Returns true when the row is new.
  /// Local status (delivered/read) of an existing row is kept. History and the
  /// conversation list carry the server's `e2e` flag; live events do not, so
  /// for those the server's own rule (an `e2e1:` envelope) is applied.
  Future<bool> _upsert(
    Sql sql,
    String convId,
    Map<String, dynamic> m, {
    String kind = 'chat',
    bool isFromHistory = false,
  }) async {
    final org = _org!;
    final user = _me!;
    final id = idText(m['id']);
    final sender = idText(m['from']);
    final text = idText(m['text']);
    final isEncrypted =
        m['e2e'] == true || (!isFromHistory && text.startsWith('e2e1:'));
    final isMine = sender.toLowerCase() == user.toLowerCase();
    final form = m['form'];
    final exists = await sql.query(
      'SELECT text, decrypt_state, plaintext, edited_ts FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [org, user, id],
    );
    // An envelope already opened (or found unreadable) stays so; a new or
    // edited one is queued for decryption.
    final old = exists.isEmpty ? null : exists.first;
    // My own sent message keeps the plaintext I wrote: the server hands the
    // envelope back trimmed to my devices, so its text differs from the one
    // sent. Only an edit (a changed edited time) is opened again.
    final isMineOpened =
        isMine &&
        old != null &&
        old['plaintext'] != null &&
        old['decrypt_state'] == 'ok' &&
        (old['edited_ts'] == null ? null : intOf(old['edited_ts'])) ==
            (m['editedTs'] == null ? null : intOf(m['editedTs']));
    final isSame =
        isMineOpened ||
        (old != null &&
            old['text'] == text &&
            (old['decrypt_state'] == 'ok' ||
                old['decrypt_state'] == 'cant_decrypt'));
    final decryptState = !isEncrypted
        ? null
        : isSame
        ? old['decrypt_state']
        : 'pending';
    final plaintext = isEncrypted && isSame ? old['plaintext'] : null;
    final values = [
      sender,
      isMine ? 1 : 0,
      kind,
      text,
      m['ts'] == null ? null : intOf(m['ts']),
      m['replyTo'] == null ? null : idText(m['replyTo']),
      isEncrypted ? 1 : 0,
      m['editedTs'] == null ? null : intOf(m['editedTs']),
      m['deleted'] == true ? 1 : 0,
      m['reactions'] == null ? null : jsonEncode(m['reactions']),
      form == null ? null : jsonEncode(form),
      decryptState,
      plaintext,
    ];
    if (exists.isEmpty) {
      await sql.insert(
        'INSERT INTO messages(sender, is_mine, kind, text, ts, reply_to, is_encrypted_unsupported, edited_ts, is_deleted, reactions_json, form_json, decrypt_state, plaintext, '
        "org_id, user_id, msg_id, conv_id, status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'sent')",
        [
          ...values.sublist(0, 4),
          intOf(m['ts']),
          ...values.sublist(5),
          org,
          user,
          id,
          convId,
        ],
      );
    } else {
      await sql.update(
        'UPDATE messages SET sender = ?, is_mine = ?, kind = ?, text = ?, ts = COALESCE(?, ts), reply_to = ?, is_encrypted_unsupported = ?, '
        'edited_ts = ?, is_deleted = ?, reactions_json = COALESCE(?, reactions_json), form_json = COALESCE(?, form_json), '
        'decrypt_state = ?, plaintext = ? '
        'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [...values, org, user, id],
      );
    }
    final preview = !isEncrypted
        ? text
        : isMineOpened
        ? '${old['plaintext']}'
        : '[encrypted message]';
    if (decryptState == 'pending') _scheduleDecrypt();
    if (isEncrypted) {
      await sql.update(
        'UPDATE conversations SET is_encrypted = 1 WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [org, user, convId],
      );
    }
    if (m['ts'] != null) {
      await sql.update(
        'UPDATE conversations SET last_text = ?, last_ts = ?, last_from = ? '
        'WHERE org_id = ? AND user_id = ? AND conv_id = ? AND last_ts <= ?',
        [preview, intOf(m['ts']), sender, org, user, convId, intOf(m['ts'])],
      );
    }
    return exists.isEmpty;
  }
}

enum _Outcome { inFlight, finished, deferred, stopped }
