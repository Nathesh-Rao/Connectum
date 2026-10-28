import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../db/app_database.dart';
import '../models/ids.dart';
import '../models/message.dart';
import '../models/outbox_entry.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';
import 'encryption_policy.dart';

enum SendResult { queued, blockedEncrypted, tooLong, invalid, noSession }

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
  );

  static const _ackTimeout = Duration(seconds: 15);
  static const _maxAttempts = 5;
  static const _historyPage = 50;
  static const _maxGapPages = 10;
  static const _cidMemory = Duration(hours: 23);
  static const couldNotConfirm = AppDatabase.couldNotConfirm;

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final ConversationRepository _conversations;
  final EncryptionPolicy _policy;

  final _lists = <String, RxList<Message>>{};
  final _historyWaiters = <String, Completer<_History>>{};
  final _inFlight = <int, OutboxEntry>{};
  final _ackTimers = <int, Timer>{};
  Timer? _wakeTimer;
  Future<void> _queue = Future.value();
  bool _isFlushing = false;
  bool _wantsFlush = false;
  bool _isSyncing = false;
  int _lastTemp = 0;
  String? _openConversation;

  String? get _org => _session.orgId;
  String? get _me => _session.userId;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen((e) {
      _queue = _queue.then((_) => _handle(e)).catchError((Object _) {});
    });
    _socket.onOnline.listen((_) => _onOnline());
    ever(_socket.connection, (state) {
      if (state != SocketState.online) _onDropped();
    });
    ever(_session.current, (_) {
      _lists.keys.toList().forEach(_reload);
    });
  }

  RxList<Message> messages(String convId) {
    final existing = _lists[convId];
    if (existing != null) return existing;
    final list = <Message>[].obs;
    _lists[convId] = list;
    _reload(convId);
    return list;
  }

  void setOpenConversation(String? convId) {
    _openConversation = convId;
    if (convId != null) _conversations.markRead(convId);
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
    final rows = await _db.query(
      'SELECT * FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? '
      "ORDER BY CASE WHEN msg_id LIKE 'temp-%' THEN 1 ELSE 0 END, ts, local_seq",
      [org, user, convId],
    );
    list.assignAll(rows.map(Message.fromRow));
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
    if (_policy.cached(convId, await _facts(convId)) ==
        EncryptionVerdict.encrypted) {
      return SendResult.blockedEncrypted;
    }
    final tempId = _tempId();
    final cid = newCid();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((sql) async {
      await ConversationRepository.ensure(sql, org, user, convId);
      await sql.insert(
        'INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, kind, text, ts, reply_to, status, local_seq, cid) '
        "VALUES(?,?,?,?,?,1,'chat',?,?,?,'pending',?,?)",
        [org, user, tempId, convId, user, body, now, replyTo, now, cid],
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
    await _reload(convId);
    await _conversations.reload();
    unawaited(flush());
    return SendResult.queued;
  }

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
    final verdict = await _policy.verdict(
      entry.convId,
      await _facts(entry.convId),
    );
    if (verdict == EncryptionVerdict.encrypted) {
      await _fail(entry, 'encrypted chat');
      return _Outcome.finished;
    }
    if (verdict == EncryptionVerdict.unknown) {
      await _defer(entry, const Duration(seconds: 15));
      return _Outcome.deferred;
    }
    final command = wireCommand(entry);
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
  static String? wireCommand(OutboxEntry e) {
    final command = _commandFor(e);
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

  static String? _commandFor(OutboxEntry e) {
    final text = '${e.payload['text']}';
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
    _inFlight.remove(outboxId);
    _ackTimers.remove(outboxId)?.cancel();
  }

  Future<void> _fail(OutboxEntry e, String reason) async {
    _settle(e.id);
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
    if (_isSyncing) return;
    _isSyncing = true;
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
      _isSyncing = false;
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
    await _db.transaction(
      (sql) => ConversationRepository.ensure(sql, org, user, 'global'),
    );
    final rows = await _db.query(
      'SELECT conv_id FROM conversations WHERE org_id = ? AND user_id = ? AND is_archived = 0',
      [org, user],
    );
    for (final row in rows) {
      if (!_socket.isOnline) return;
      await _syncConversation(idText(row['conv_id']));
    }
    await _conversations.reload();
  }

  /// Fetches the latest page. When my last known server id is not in it,
  /// pages backwards with `before` until it is, the history ends, or the cap
  /// of pages is reached (then the conversation is flagged as having a gap).
  /// The id is looked for in the page; ids are never compared as numbers.
  Future<void> _syncConversation(String convId) async {
    final lastKnown = await _cursor(convId);
    final latest = await _fetchHistory(convId);
    if (latest == null || lastKnown == null || latest.items.isEmpty) return;
    if (_holds(latest, lastKnown)) return;
    var before = idText(latest.items.first['id']);
    for (var page = 0; page < _maxGapPages; page++) {
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
      _historyWaiters.remove(key);
    }
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
    final status = delivered && entry.convId.startsWith('dm:')
        ? MessageStatus.delivered.name
        : MessageStatus.sent.name;
    await _db.transaction((sql) async {
      final exists = await sql.query(
        'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [_org, _me, serverId],
      );
      if (exists.isNotEmpty) {
        await sql.update(
          'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [_org, _me, entry.refId],
        );
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

  Future<void> _onError(Map<String, dynamic> e) async {
    final code = idText(e['code']);
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
    await _db.update(
      'UPDATE messages SET is_deleted = 1 WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [_org, _me, id],
    );
    await _reloadAll();
  }

  Future<void> _onReaction(Map<String, dynamic> e) async {
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
        ts: intOf(e['ts']),
        isNew: isNew,
        isMine: idText(e['from']).toLowerCase() == user.toLowerCase(),
      );
      await _setCursor(sql, convId, id);
    });
    if (_openConversation == convId && convId.startsWith('dm:')) {
      unawaited(_socket.sendCommand('/read dm ${convId.substring(3)}'));
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
      await _noteIncoming(
        sql,
        convId,
        id: idText(data['id']),
        ts: intOf(data['ts']),
        isNew: isNew,
        isMine: idText(data['from']).toLowerCase() == user.toLowerCase(),
      );
      await _setCursor(sql, convId, idText(data['id']));
    });
    await _reload(convId);
    await _conversations.reload();
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
        await _setCursor(sql, convId, null);
        await sql.update(
          'UPDATE sync_cursor SET has_more = ?, next_id = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [hasMore ? 1 : 0, next, org, user, convId],
        );
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
    await _reload(convId);
    await _conversations.reload();
    final waiter = _historyWaiters[isOlder ? 'older:$convId' : convId];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(_History(items, unknown, hasMore: hasMore, next: next));
    }
  }

  // ---- unread ---------------------------------------------------------------
  // Local only, not shared across devices. Unread = messages from others newer
  // than this thread's "last opened" marker, judged by the server ts and the
  // position in the thread, never by the phone's clock or by comparing ids.

  Future<void> _setMarker(
    Sql sql,
    String convId,
    int ts,
    String id,
  ) => sql.update(
    'UPDATE conversations SET read_ts = ?, read_id = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
    [ts, id, _org, _me, convId],
  );

  /// A live message. While its thread is open it moves the marker; otherwise
  /// it counts. A thread with no marker yet gets one just before this message.
  Future<void> _noteIncoming(
    Sql sql,
    String convId, {
    required String id,
    required int ts,
    required bool isNew,
    required bool isMine,
  }) async {
    if (!isNew || isMine) return;
    if (_openConversation == convId) {
      await _setMarker(sql, convId, ts, id);
      return;
    }
    final rows = await sql.query(
      'SELECT read_ts FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    if (rows.isEmpty || rows.first['read_ts'] == null) {
      await _setMarker(sql, convId, ts - 1, '');
    }
    await sql.update(
      'UPDATE conversations SET unread = unread + 1 WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
  }

  /// The latest history page (oldest first). A thread's first sync counts 0
  /// and sets the marker to its newest message. Later pages count the new
  /// messages from others that come after the marker.
  Future<void> _countHistory(
    Sql sql,
    String convId,
    List<Map<String, dynamic>> items,
    List<int> fresh,
  ) async {
    if (items.isEmpty) return;
    final rows = await sql.query(
      'SELECT read_ts, read_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    final readTs = rows.isEmpty || rows.first['read_ts'] == null
        ? null
        : intOf(rows.first['read_ts']);
    final newest = items.last;
    if (readTs == null) {
      await _setMarker(sql, convId, intOf(newest['ts']), idText(newest['id']));
      return;
    }
    final readId = idText(rows.first['read_id']);
    final at = readId.isEmpty
        ? -1
        : items.indexWhere((i) => idText(i['id']) == readId);
    final count = fresh
        .where((i) => at >= 0 ? i > at : intOf(items[i]['ts']) > readTs)
        .length;
    if (count == 0) return;
    if (_openConversation == convId) {
      await _setMarker(sql, convId, intOf(newest['ts']), idText(newest['id']));
      return;
    }
    await sql.update(
      'UPDATE conversations SET unread = unread + ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [count, _org, _me, convId],
    );
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
      'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [org, user, id],
    );
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
    ];
    if (exists.isEmpty) {
      await sql.insert(
        'INSERT INTO messages(sender, is_mine, kind, text, ts, reply_to, is_encrypted_unsupported, edited_ts, is_deleted, reactions_json, form_json, '
        "org_id, user_id, msg_id, conv_id, status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'sent')",
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
        'edited_ts = ?, is_deleted = ?, reactions_json = COALESCE(?, reactions_json), form_json = COALESCE(?, form_json) '
        'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [...values, org, user, id],
      );
    }
    final preview = isEncrypted ? '[encrypted message]' : text;
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
