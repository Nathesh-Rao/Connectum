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
  const _History(this.items, this.unknown);

  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> unknown;
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
  static const couldNotConfirm = "couldn't confirm delivery";

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final ConversationRepository _conversations;
  final EncryptionPolicy _policy;

  final _lists = <String, RxList<Message>>{};
  final _historyWaiters = <String, Completer<_History>>{};
  Future<void> _queue = Future.value();
  OutboxEntry? _inFlight;
  Timer? _ackTimer;
  Timer? _wakeTimer;
  bool _isFlushing = false;
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

  bool isEncryptedForSending(String convId, {required bool hasE2eHistory}) =>
      _policy.cached(convId, hasE2eHistory) == EncryptionVerdict.encrypted;

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

  Future<bool> _hasE2eHistory(String convId) async {
    final rows = await _db.query(
      'SELECT is_encrypted FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    return rows.isNotEmpty && intOf(rows.first['is_encrypted']) == 1;
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
    if (_policy.cached(convId, await _hasE2eHistory(convId)) ==
        EncryptionVerdict.encrypted) {
      return SendResult.blockedEncrypted;
    }
    final tempId = _tempId();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((sql) async {
      await ConversationRepository.ensure(sql, org, user, convId);
      await sql.insert(
        'INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, kind, text, ts, reply_to, status, local_seq) '
        "VALUES(?,?,?,?,?,1,'chat',?,?,?,'pending',?)",
        [org, user, tempId, convId, user, body, now, replyTo, now],
      );
      await sql.insert(
        'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts) '
        "VALUES(?,?,?,?,?,?,'pending',?)",
        [
          org,
          user,
          convId,
          replyTo == null ? 'message' : 'reply',
          jsonEncode({'text': body, 'replyTo': replyTo}),
          tempId,
          now,
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
        "UPDATE outbox SET status = 'pending', retry_count = 0, next_attempt_ts = 0, last_error = NULL "
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

  /// One chat message is in flight at a time, in outbox order, so an ack can
  /// only belong to that message and order survives retries.
  Future<void> flush() async {
    if (_isFlushing) return;
    _isFlushing = true;
    try {
      while (_socket.isOnline && _session.hasSession) {
        if (await _countSending() > 0) return;
        final entry = await _nextPending();
        if (entry == null) {
          await _scheduleWake();
          return;
        }
        final outcome = await _send(entry);
        if (outcome == _Outcome.inFlight || outcome == _Outcome.deferred) {
          return;
        }
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<int> _countSending() async {
    final rows = await _db.query(
      "SELECT COUNT(*) AS n FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'sending' AND kind IN ('message','reply','edit')",
      [_org, _me],
    );
    return intOf(rows.first['n']);
  }

  Future<OutboxEntry?> _nextPending() async {
    final rows = await _db.query(
      "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'pending' "
      "AND kind IN ('message','reply','edit') AND next_attempt_ts <= ? ORDER BY id LIMIT 1",
      [_org, _me, DateTime.now().millisecondsSinceEpoch],
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

  Future<_Outcome> _send(OutboxEntry entry) async {
    if (entry.retryCount >= _maxAttempts) {
      await _fail(entry, 'too many attempts');
      return _Outcome.finished;
    }
    final verdict = await _policy.verdict(
      entry.convId,
      await _hasE2eHistory(entry.convId),
    );
    if (verdict == EncryptionVerdict.encrypted) {
      await _fail(entry, 'encrypted chat');
      return _Outcome.finished;
    }
    if (verdict == EncryptionVerdict.unknown) {
      await _defer(entry, const Duration(seconds: 15));
      return _Outcome.deferred;
    }
    final command = _commandFor(entry);
    if (command == null) {
      await _fail(entry, 'unsupported in this conversation');
      return _Outcome.finished;
    }
    final cursor = await _cursor(entry.convId);
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET status = 'sending', attempt_ts = ?, retry_count = retry_count + 1, cursor_at_send = ? WHERE id = ?",
        [DateTime.now().millisecondsSinceEpoch, cursor, entry.id],
      );
      if (entry.kind != 'edit') {
        await sql.update(
          "UPDATE messages SET status = 'sending' WHERE org_id = ? AND user_id = ? AND msg_id = ?",
          [_org, _me, entry.refId],
        );
      }
    });
    _inFlight = OutboxEntry(
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
      attemptTs: DateTime.now().millisecondsSinceEpoch,
    );
    final sent = await _socket.sendCommand(command);
    if (!sent) {
      await _backToPending(_inFlight!, countAttempt: false);
      _inFlight = null;
      return _Outcome.deferred;
    }
    _ackTimer?.cancel();
    _ackTimer = Timer(_ackTimeout, _onAckTimeout);
    await _reload(entry.convId);
    return _Outcome.inFlight;
  }

  String? _commandFor(OutboxEntry e) {
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

  Future<void> _fail(OutboxEntry e, String reason) async {
    if (_inFlight?.id == e.id) {
      _inFlight = null;
      _ackTimer?.cancel();
    }
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
    _ackTimer?.cancel();
    _inFlight = null;
    for (final waiter in _historyWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('dropped'));
    }
  }

  Future<void> _onAckTimeout() async {
    final entry = _inFlight;
    if (entry == null || !_socket.isOnline) return;
    await _reconcile(entry);
    unawaited(flush());
  }

  // ---- reconnect and reconcile --------------------------------------------

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
        await _reconcile(OutboxEntry.fromRow(row));
      }
      await _syncAll();
      await flush();
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> syncNow() => _onOnline();

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
      await _fetchHistory(idText(row['conv_id']));
    }
    await _conversations.reload();
  }

  Future<_History?> _fetchHistory(String convId) async {
    final existing = _historyWaiters[convId];
    if (existing != null) {
      return existing.future
          .then<_History?>((h) => h)
          .catchError((Object _) => null);
    }
    final kind = ConversationRepository.kindOf(convId);
    final target = ConversationRepository.targetOf(convId);
    final waiter = Completer<_History>();
    _historyWaiters[convId] = waiter;
    try {
      final sent = await _socket.sendCommand(
        kind == 'global' ? '/history global' : '/history $kind $target',
      );
      if (!sent) return null;
      return await waiter.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    } finally {
      _historyWaiters.remove(convId);
    }
  }

  /// Duplicate protection for the single in-flight message. The protocol has
  /// no client id, so after a drop or an ack timeout the history is fetched
  /// and searched before anything is re-sent.
  ///
  /// Match: a message in the fetched history that is from me, kind `chat`,
  /// has exactly the same text (and replyTo), has a server id above
  /// `cursor_at_send` and was not already held locally before the merge.
  /// Found -> adopt its id as the ack. Not found -> re-send only if the
  /// history clearly reaches back past the cursor (fewer than 50 items, so it
  /// is the whole thread, or it holds an id <= the cursor). Otherwise, or if
  /// the history cannot be fetched while online, the message is failed with
  /// "couldn't confirm delivery" and never auto-resent. Edits are idempotent
  /// and are simply re-queued.
  Future<void> _reconcile(OutboxEntry entry) async {
    _ackTimer?.cancel();
    if (entry.kind == 'edit') {
      _inFlight = null;
      await _backToPending(entry, countAttempt: true);
      return;
    }
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
      _inFlight = null;
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

  Future<void> _ack(
    String convId,
    Map<String, dynamic> e, {
    bool delivered = false,
  }) async {
    final entry = _inFlight;
    if (entry == null || entry.kind == 'edit') return;
    if (entry.convId.toLowerCase() != convId.toLowerCase()) return;
    await _adopt(entry, idText(e['id']), intOf(e['ts']), delivered: delivered);
    unawaited(flush());
  }

  Future<void> _adopt(
    OutboxEntry entry,
    String serverId,
    int ts, {
    bool delivered = false,
  }) async {
    _ackTimer?.cancel();
    if (_inFlight?.id == entry.id) _inFlight = null;
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
          "UPDATE messages SET is_mine = 1, status = CASE WHEN status IN ('delivered','read') THEN status ELSE ? END WHERE org_id = ? AND user_id = ? AND msg_id = ?",
          [status, _org, _me, serverId],
        );
      } else {
        await sql.update(
          'UPDATE messages SET msg_id = ?, ts = ?, status = ?, fail_reason = NULL, local_seq = 0 '
          'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [serverId, ts, status, _org, _me, entry.refId],
        );
      }
      await sql.update('DELETE FROM outbox WHERE id = ?', [entry.id]);
      await _bumpCursor(sql, entry.convId, serverId);
    });
    await _reload(entry.convId);
    await _conversations.reload();
  }

  Future<void> _bumpCursor(
    Sql sql,
    String convId,
    String serverId, {
    int? now,
  }) async {
    final next = idNumber(serverId);
    final rows = await sql.query(
      'SELECT last_server_id FROM sync_cursor WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [_org, _me, convId],
    );
    final current = rows.isEmpty
        ? null
        : idNumber(rows.first['last_server_id']);
    final keep = next == null || (current != null && current >= next)
        ? current?.toString()
        : serverId;
    if (rows.isEmpty) {
      await sql.insert(
        'INSERT INTO sync_cursor(org_id, user_id, conv_id, last_server_id, last_history_now, synced_ts) VALUES(?,?,?,?,?,?)',
        [_org, _me, convId, keep, now, DateTime.now().millisecondsSinceEpoch],
      );
    } else {
      await sql.update(
        'UPDATE sync_cursor SET last_server_id = ?, last_history_now = COALESCE(?, last_history_now), synced_ts = ? '
        'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [keep, now, DateTime.now().millisecondsSinceEpoch, _org, _me, convId],
      );
    }
  }

  Future<void> _onError(Map<String, dynamic> e) async {
    final entry = _inFlight;
    final conv = e['conv'];
    if (entry == null || !entry.isChat || conv == null) return;
    if (idText(conv).toLowerCase() != entry.convId.toLowerCase()) return;
    await _fail(entry, idText(e['code'] ?? e['text']));
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
    final entry = _inFlight;
    if (entry != null && entry.kind == 'edit' && entry.refId == id) {
      _ackTimer?.cancel();
      _inFlight = null;
      await _db.update('DELETE FROM outbox WHERE id = ?', [entry.id]);
      unawaited(flush());
    }
    await _reloadAll();
  }

  Future<void> _onEditDenied(Map<String, dynamic> e) async {
    final entry = _inFlight;
    if (entry == null || entry.kind != 'edit') return;
    if (entry.refId != idText(e['messageId'])) return;
    await _fail(entry, 'edit denied: ${idText(e['reason'])}');
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
      final isMine = idText(e['from']).toLowerCase() == user.toLowerCase();
      if (isNew && !isMine && _openConversation != convId) {
        await sql.update(
          'UPDATE conversations SET unread = unread + 1 WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [org, user, convId],
        );
      }
      await _bumpCursor(sql, convId, id);
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
      await _upsert(sql, convId, data, kind: 'form');
      await _bumpCursor(sql, convId, idText(data['id']));
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
    final items = ((e['list'] as List?) ?? [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final unknown = <Map<String, dynamic>>[];
    await _db.transaction((sql) async {
      await ConversationRepository.ensure(sql, org, user, convId);
      for (final item in items) {
        final isNew = await _upsert(
          sql,
          convId,
          item,
          kind: idText(item['kind']).isEmpty ? 'chat' : idText(item['kind']),
        );
        if (isNew) unknown.add(item);
      }
      final ids = items.map((i) => idNumber(i['id'])).whereType<int>();
      final newest = ids.isEmpty ? null : ids.reduce((a, b) => a > b ? a : b);
      await _bumpCursor(
        sql,
        convId,
        newest?.toString() ?? '',
        now: intOf(e['now']),
      );
    });
    await _reload(convId);
    await _conversations.reload();
    final waiter = _historyWaiters[convId];
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(_History(items, unknown));
    }
  }

  /// Inserts or updates one server message. Returns true when the row is new.
  /// Local status (delivered/read) of an existing row is kept.
  Future<bool> _upsert(
    Sql sql,
    String convId,
    Map<String, dynamic> m, {
    String kind = 'chat',
  }) async {
    final org = _org!;
    final user = _me!;
    final id = idText(m['id']);
    final sender = idText(m['from']);
    final text = idText(m['text']);
    final isEncrypted = text.startsWith('e2e1:');
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

enum _Outcome { inFlight, finished, deferred }
