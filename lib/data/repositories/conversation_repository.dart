import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../db/app_database.dart';
import '../e2e/e2e_models.dart';
import '../models/chat_thread.dart';
import '../models/conversation.dart';
import '../models/ids.dart';
import '../models/thread_names.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'e2e_repository.dart';

class ConversationRepository extends GetxService {
  ConversationRepository(this._db, this._session, this._socket, this._e2e);

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final E2eRepository _e2e;

  final conversations = <Conversation>[].obs;
  final isLoaded = false.obs;

  /// True once the server lists of this organisation and user have been
  /// written to SQLite at least once since the session was set.
  final isSynced = false.obs;

  /// True when [requestLists] has neither finished nor failed within
  /// [_syncGrace]: only lets the empty state replace the skeleton. It never
  /// marks the lists as synced; a late finish still sets [isSynced] as usual.
  final hasSyncStalled = false.obs;
  final loadError = RxnString();
  String? _scope;

  /// The `<org>/<user>` the rows in [conversations] were read for. A list read
  /// for any other scope is never shown.
  String? listScope;
  Completer<void>? _listsReady;
  Timer? _syncGraceTimer;
  final _readTimers = <String, Timer>{};
  final _deliveredTimers = <String, Timer>{};
  final _receipts = StreamController<String>.broadcast();
  Timer? _namesTimer;
  Timer? _threadNamesTimer;

  static const _syncGrace = Duration(seconds: 10);
  static const _readDelay = Duration(milliseconds: 600);
  static const _deliveredDelay = Duration(seconds: 1);

  /// A direct conversation whose peer read or delivered position changed.
  Stream<String> get receiptsChanged => _receipts.stream;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    _scope = '${_session.orgId}/${_session.userId}';
    ever(_session.current, (_) {
      final scope = '${_session.orgId}/${_session.userId}';
      if (scope != _scope) {
        _scope = scope;
        listScope = null;
        conversations.clear();
        loadError.value = null;
        isLoaded.value = false;
        isSynced.value = false;
        hasSyncStalled.value = false;
        _syncGraceTimer?.cancel();
        for (final timer in [
          ..._readTimers.values,
          ..._deliveredTimers.values,
        ]) {
          timer.cancel();
        }
        _readTimers.clear();
        _deliveredTimers.clear();
        if (_session.orgId != null) {
          _syncGraceTimer = Timer(_syncGrace, () {
            if (!isSynced.value) hasSyncStalled.value = true;
          });
        }
      }
      reload();
    });
    reload();
  }

  /// Reads the list from SQLite. Each row carries the newest message of its
  /// thread (joined on the newest rowid by ts), so the list can show a
  /// preview of the right kind without a query per row.
  Future<void> reload() async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) {
      listScope = null;
      conversations.clear();
      return;
    }
    try {
      final list = await readFor(org, user);
      if (org != _session.orgId || user != _session.userId) return;
      listScope = '$org/$user';
      conversations.assignAll(list);
      loadError.value = null;
      isLoaded.value = true;
    } catch (e) {
      loadError.value = 'Could not read your chats.';
      isLoaded.value = true;
    }
  }

  /// The list of one organisation and person, read from SQLite.
  Future<List<Conversation>> readFor(String org, String user) async {
    final rows = await _db.query(
      'SELECT c.*, m.text AS lm_text, m.kind AS lm_kind, m.is_mine AS lm_mine, m.status AS lm_status, '
      'm.is_encrypted_unsupported AS lm_e2e, m.plaintext AS lm_plain, m.decrypt_state AS lm_dstate, m.is_deleted AS lm_deleted, m.form_json AS lm_form '
      'FROM conversations c LEFT JOIN messages m ON m.rowid = ('
      'SELECT x.rowid FROM messages x WHERE x.org_id = c.org_id AND x.user_id = c.user_id AND x.conv_id = c.conv_id '
      'ORDER BY x.ts DESC, x.local_seq DESC LIMIT 1) '
      'WHERE c.org_id = ? AND c.user_id = ? ORDER BY c.last_ts DESC',
      [org, user],
    );
    return rows.map(Conversation.fromRow).toList();
  }

  /// Asks the server for DM threads, groups and hosts and waits until the
  /// last reply (`hosts`) has been written to SQLite.
  Future<void> requestLists() async {
    final scope = _scope;
    _listsReady = Completer<void>();
    _syncGraceTimer?.cancel();
    _syncGraceTimer = Timer(_syncGrace, () {
      if (!isSynced.value) hasSyncStalled.value = true;
    });
    await _socket.sendCommand('/conversations');
    await _socket.sendCommand('/groups');
    await _socket.sendCommand('/hosts');
    await _listsReady!.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
    // Last, so its archive, pin, mute and unread win over the lists above.
    await syncInbox();
    await loadCareNames();
    await loadRecordNames();
    await flushPositions();
    if (scope != _scope) return;
    _syncGraceTimer?.cancel();
    isSynced.value = true;
  }

  // ---- server inbox state ----------------------------------------------------

  /// Every conversation I have a state for, from `conv.list {full:true}`:
  /// unread (the server's number, at most 99, `unreadMore` past it), the read
  /// position, the newest id, pin, mute, archive, the delivered position and,
  /// for a direct one, how far the other person has read and received. It is
  /// the source of those fields; names, members and previews still come from
  /// the lists and history. A read position waiting to be sent keeps the
  /// local zero until it is.
  Future<void> syncInbox() async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null || !_socket.isOnline) return;
    final Map<String, dynamic> data;
    try {
      data = await _socket.sdCall('conv.list', {'full': true});
    } on SocketCallError catch (_) {
      return;
    }
    final changed = <String>[];
    await _db.transaction((sql) async {
      for (final r in (data['conversations'] as List? ?? []).cast<Map>()) {
        final kind = idText(r['kind']);
        final String convId;
        final String title;
        switch (kind) {
          case 'dm':
            title = idText(r['with']).toLowerCase();
            convId = 'dm:$title';
          case 'group':
            title = idText(r['group']);
            convId = 'group:$title';
          case 'global':
            title = 'Global';
            convId = 'global';
          default:
            continue;
        }
        await ensure(sql, org, user, convId, title: title);
        final known = await sql.query(
          'SELECT peer_read_id, peer_delivered_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [org, user, convId],
        );
        final peerRead = _forward(known.first['peer_read_id'], r['peerReadId']);
        final peerDelivered = _forward(
          known.first['peer_delivered_id'],
          r['peerDeliveredId'],
        );
        await sql.update(
          'UPDATE conversations SET last_id = ?, read_id = ?, '
          'unread = CASE WHEN pending_read_id IS NULL THEN ? ELSE unread END, '
          'unread_more = CASE WHEN pending_read_id IS NULL THEN ? ELSE 0 END, '
          'is_pinned = ?, pinned_ts = ?, is_muted = ?, is_archived = ?, delivered_id = ?, '
          'peer_read_id = ?, peer_delivered_id = ?, avatar = COALESCE(?, avatar) '
          'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [
            _idOrNull(r['lastId']),
            _idOrNull(r['readId']),
            intOf(r['unread']),
            r['unreadMore'] == true ? 1 : 0,
            r['pinned'] == true ? 1 : 0,
            r['pinnedTs'] == null ? null : intOf(r['pinnedTs']),
            r['muted'] == true ? 1 : 0,
            r['archived'] == true ? 1 : 0,
            _idOrNull(r['deliveredId']),
            peerRead,
            peerDelivered,
            r['avatar'] == null ? null : idText(r['avatar']),
            org,
            user,
            convId,
          ],
        );
        if (kind == 'dm') changed.add(convId);
      }
    });
    await reload();
    changed.forEach(_receipts.add);
  }

  /// The titles of the record conversations I am in, the ones I may rename and
  /// the ones their form keeps out of the main list, from `record.names`. Kept
  /// per conversation, so they show offline. A failed call keeps what is stored.
  Future<void> loadRecordNames() async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null || !_socket.isOnline) return;
    final Map<String, dynamic> data;
    try {
      data = await _socket.sdCall('record.names', {});
    } on SocketCallError catch (_) {
      return;
    }
    if (org != _session.orgId || user != _session.userId) return;
    final record = RecordNames.fromReply(data);
    await _db.transaction((sql) async {
      await sql.update(
        'UPDATE conversations SET is_list_hidden = 0, can_rename = 0 '
        'WHERE org_id = ? AND user_id = ? AND (is_list_hidden = 1 OR can_rename = 1)',
        [org, user],
      );
      for (final g in record.hidden) {
        await sql.update(
          'UPDATE conversations SET is_list_hidden = 1 '
          'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [org, user, 'group:$g'],
        );
      }
      for (final g in record.canRename) {
        await sql.update(
          'UPDATE conversations SET can_rename = 1 '
          'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [org, user, 'group:$g'],
        );
      }
      for (final entry in record.names.entries) {
        await sql.update(
          'UPDATE conversations SET thread_title = ? '
          'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [entry.value, org, user, 'group:${entry.key}'],
        );
      }
    });
    await reload();
  }

  /// The titles of the people's shared threads (`care-<username>`): the
  /// person's name from `care.names`, and for my own thread the organisation's
  /// name from `org.name`, as the web does. Stored like the record titles; a
  /// failed call keeps what is stored, and until a name is known the tidied
  /// username shows.
  Future<void> loadCareNames() async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null || !_socket.isOnline) return;
    var names = const <String, String>{};
    var orgName = '';
    try {
      orgName = CareNames.orgFromReply(await _socket.sdCall('org.name', {}));
    } on SocketCallError catch (_) {}
    try {
      names = CareNames.fromReply(await _socket.sdCall('care.names', {}));
    } on SocketCallError catch (_) {}
    if (org != _session.orgId || user != _session.userId) return;
    final me = user.toLowerCase();
    final titles = {...names, if (orgName.isNotEmpty) me: orgName};
    if (titles.isEmpty) return;
    await _db.transaction((sql) async {
      for (final entry in titles.entries) {
        await sql.update(
          'UPDATE conversations SET thread_title = ? '
          'WHERE org_id = ? AND user_id = ? AND LOWER(conv_id) = ?',
          [entry.value, org, user, 'group:care-${entry.key}'],
        );
      }
    });
    await reload();
  }

  /// Renames a record conversation for everyone in it (`record.rename`; only
  /// the person who saved the record may). The new title shows at once and is
  /// put back if the server refuses; an empty [name] asks for the made title
  /// back. Throws the [SocketCallError] of a refusal.
  Future<void> renameRecord(Conversation c, String name) async {
    final org = _session.orgId;
    final user = _session.userId;
    final group = ChatThread.groupName(c.convId);
    final id = group == null ? null : ChatThread.recordId(group);
    if (org == null || user == null || group == null || id == null) {
      throw const SocketCallError(
        'invalid',
        'That conversation cannot be renamed.',
      );
    }
    final wanted = name.trim();
    final shown = wanted.isEmpty ? ChatThread.fallbackTitle(group) : wanted;
    _setTitle(c.convId, shown);
    final RecordRename done;
    try {
      done = RecordRename.fromReply(
        await _socket.sdCall('record.rename', {'id': id, 'name': wanted}),
      );
    } on SocketCallError {
      _setTitle(c.convId, c.title, onlyIf: shown);
      rethrow;
    }
    if (org != _session.orgId || user != _session.userId) return;
    await _db.update(
      'UPDATE conversations SET thread_title = ? '
      'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [done.title, org, user, c.convId],
    );
    await reload();
  }

  /// Changes the shown title in the list only; with [onlyIf] only while it is
  /// still that text (a refresh in between wins).
  void _setTitle(String convId, String title, {String? onlyIf}) {
    final i = conversations.indexWhere((x) => x.convId == convId);
    if (i < 0) return;
    if (onlyIf != null && conversations[i].title != onlyIf) return;
    conversations[i] = conversations[i].withTitle(title);
  }

  /// Bursts of events (a record edited, a thread joined) become one read.
  void _scheduleRecordNames() {
    _namesTimer?.cancel();
    _namesTimer = Timer(const Duration(milliseconds: 600), loadRecordNames);
  }

  /// A thread joined during the session needs its name too: the web asks for
  /// the care names, the organisation's name and the record names again.
  void _scheduleThreadNames() {
    _threadNamesTimer?.cancel();
    _threadNamesTimer = Timer(const Duration(milliseconds: 600), () async {
      await loadCareNames();
      await loadRecordNames();
    });
  }

  /// A position of 0 means none. Ids are stored as text.
  static String? _idOrNull(Object? id) {
    final text = idText(id);
    return text.isEmpty || text == '0' ? null : text;
  }

  /// The newer of what is stored and what the server says, never going back.
  static String? _forward(Object? stored, Object? incoming) {
    final next = _idOrNull(incoming);
    final old = _idOrNull(stored);
    if (next == null) return old;
    if (old == null) return next;
    final a = numericId(next);
    final b = numericId(old);
    return a != null && b != null && a < b ? old : next;
  }

  /// Pin, unpin, mute or unmute: kept on the server, so it needs a connection.
  Future<void> setPinned(String convId, {required bool isPinned}) =>
      _toggle(convId, isPinned ? 'conv.pin' : 'conv.unpin');

  Future<void> setMuted(String convId, {required bool isMuted}) =>
      _toggle(convId, isMuted ? 'conv.mute' : 'conv.unmute');

  Future<void> _toggle(String convId, String action) async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    final data = await _socket.sdCall(action, {'id': convId});
    final c = (data['conversation'] as Map?) ?? {};
    await _db.update(
      'UPDATE conversations SET is_pinned = ?, pinned_ts = ?, is_muted = ? '
      'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [
        c['pinned'] == true ? 1 : 0,
        c['pinnedTs'] == null ? null : intOf(c['pinnedTs']),
        c['muted'] == true ? 1 : 0,
        org,
        user,
        convId,
      ],
    );
    await reload();
  }

  /// The messages up to [upToId] are on screen. Clears the unread count here
  /// at once and sends `conv.read` (debounced, forward only). Offline, the
  /// newest position is kept per conversation and sent after a reconnect. It
  /// lives outside the message outbox, so it never waits behind a send. Not
  /// wired to any screen yet: the conversation screen calls it when messages
  /// are actually visible.
  Future<void> markRead(String convId, String upToId) async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    await _db.update(
      'UPDATE conversations SET unread = 0, unread_more = 0 WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [org, user, convId],
    );
    final up = numericId(upToId);
    final rows = await _db.query(
      'SELECT pending_read_id, read_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [org, user, convId],
    );
    if (rows.isNotEmpty && up != null) {
      final done = [
        numericId(rows.first['pending_read_id']) ?? 0,
        numericId(rows.first['read_id']) ?? 0,
      ].reduce((a, b) => a > b ? a : b);
      if (up > done) {
        await _db.update(
          'UPDATE conversations SET pending_read_id = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          ['$up', org, user, convId],
        );
        _readTimers[convId]?.cancel();
        _readTimers[convId] = Timer(_readDelay, () => _flushRead(convId));
      }
    }
    await reload();
  }

  Future<void> _flushRead(String convId) async {
    _readTimers.remove(convId);
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null || !_socket.isOnline) return;
    final rows = await _db.query(
      'SELECT pending_read_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [org, user, convId],
    );
    final up = rows.isEmpty ? null : numericId(rows.first['pending_read_id']);
    if (up == null) return;
    try {
      final data = await _socket.sdCall('conv.read', {
        'id': convId,
        'upTo': up,
      });
      final c = (data['conversation'] as Map?) ?? {};
      await _db.update(
        'UPDATE conversations SET read_id = ?, '
        'unread = CASE WHEN pending_read_id = ? THEN ? ELSE unread END, '
        'unread_more = CASE WHEN pending_read_id = ? THEN ? ELSE unread_more END, '
        'pending_read_id = CASE WHEN pending_read_id = ? THEN NULL ELSE pending_read_id END '
        'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [
          _idOrNull(c['readId']),
          '$up',
          intOf(c['unread']),
          '$up',
          c['unreadMore'] == true ? 1 : 0,
          '$up',
          org,
          user,
          convId,
        ],
      );
    } on SocketCallError catch (e) {
      if (e.isConnectionGap) return;
      await _db.update(
        'UPDATE conversations SET pending_read_id = NULL WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [org, user, convId],
      );
    }
    await reload();
  }

  /// Messages from the other person of a direct conversation have arrived, up
  /// to [upToId]: tells the server so their delivery tick can show (debounced,
  /// forward only, only while online; held and sent after a reconnect).
  Future<void> noteDelivered(String convId, String upToId) async {
    final org = _session.orgId;
    final user = _session.userId;
    final up = numericId(upToId);
    if (org == null ||
        user == null ||
        up == null ||
        !convId.startsWith('dm:')) {
      return;
    }
    final rows = await _db.query(
      'SELECT pending_delivered_id, delivered_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [org, user, convId],
    );
    if (rows.isEmpty) return;
    final done = [
      numericId(rows.first['pending_delivered_id']) ?? 0,
      numericId(rows.first['delivered_id']) ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    if (up <= done) return;
    await _db.update(
      'UPDATE conversations SET pending_delivered_id = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      ['$up', org, user, convId],
    );
    _deliveredTimers[convId]?.cancel();
    _deliveredTimers[convId] = Timer(
      _deliveredDelay,
      () => _flushDelivered(convId),
    );
  }

  Future<void> _flushDelivered(String convId) async {
    _deliveredTimers.remove(convId);
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null || !_socket.isOnline) return;
    final rows = await _db.query(
      'SELECT pending_delivered_id FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [org, user, convId],
    );
    final up = rows.isEmpty
        ? null
        : numericId(rows.first['pending_delivered_id']);
    if (up == null) return;
    try {
      final data = await _socket.sdCall('conv.delivered', {
        'id': convId,
        'upTo': up,
      });
      final c = (data['conversation'] as Map?) ?? {};
      await _db.update(
        'UPDATE conversations SET delivered_id = ?, '
        'pending_delivered_id = CASE WHEN pending_delivered_id = ? THEN NULL ELSE pending_delivered_id END '
        'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [_idOrNull(c['deliveredId']) ?? '$up', '$up', org, user, convId],
      );
    } on SocketCallError catch (e) {
      if (e.isConnectionGap) return;
      await _db.update(
        'UPDATE conversations SET pending_delivered_id = NULL WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [org, user, convId],
      );
    }
  }

  /// Sends the read and delivered positions that were kept while offline.
  Future<void> flushPositions() async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null || !_socket.isOnline) return;
    final rows = await _db.query(
      'SELECT conv_id, pending_read_id, pending_delivered_id FROM conversations '
      'WHERE org_id = ? AND user_id = ? AND (pending_read_id IS NOT NULL OR pending_delivered_id IS NOT NULL)',
      [org, user],
    );
    for (final r in rows) {
      final id = idText(r['conv_id']);
      if (r['pending_delivered_id'] != null) await _flushDelivered(id);
      if (r['pending_read_id'] != null) await _flushRead(id);
    }
  }

  /// Who of a group has read my message (only its author may ask). On demand.
  Future<Map<String, dynamic>> readers(String convId, String messageId) {
    final id = numericId(messageId);
    return _socket.sdCall('conv.readers', {
      'id': convId,
      'messageId': id ?? messageId,
    });
  }

  static String kindOf(String convId) =>
      convId == 'global' ? 'global' : convId.split(':').first;

  static String targetOf(String convId) =>
      convId == 'global' ? '' : convId.substring(convId.indexOf(':') + 1);

  static Future<void> ensure(
    Sql sql,
    String org,
    String user,
    String convId, {
    String? title,
  }) => sql
      .insert(
        'INSERT OR IGNORE INTO conversations(org_id, user_id, conv_id, kind, title) VALUES(?,?,?,?,?)',
        [
          org,
          user,
          convId,
          kindOf(convId),
          title ?? (convId == 'global' ? 'Global' : targetOf(convId)),
        ],
      )
      .then((_) => 0);

  /// The list row of an encrypted thread carries the last envelope. When no
  /// message row of the thread holds it yet, it is opened here so the preview
  /// can show the text.
  Future<void> _decryptPreviews(List<Map> list) async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    var isChanged = false;
    for (final item in list) {
      final text = idText(item['text']);
      if (item['e2e'] != true || !text.startsWith('e2e1:')) continue;
      final conv = 'dm:${idText(item['with']).toLowerCase()}';
      final known = await _db.query(
        'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [org, user, idText(item['id'])],
      );
      if (known.isNotEmpty) continue;
      final reading = await _e2e.open(text: text, convId: conv);
      if (reading.state != E2eReadState.ok) continue;
      await _db.update(
        'UPDATE conversations SET last_text = ? WHERE org_id = ? AND user_id = ? '
        "AND conv_id = ? AND last_ts = ? AND last_text = '[encrypted message]'",
        [reading.text, org, user, conv, intOf(item['ts'])],
      );
      isChanged = true;
    }
    if (isChanged) await reload();
  }

  Future<void> _onEvent(Map<String, dynamic> e) async {
    if (!_socket.isCurrent(e)) return;
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    switch (e['type']) {
      case 'sd_event':
        final event = e['event'];
        if (event == 'submissions_changed' || event == 'resync') {
          _scheduleRecordNames();
        }
        return;
      case 'conversations':
        await _db.transaction((sql) async {
          for (final item in (e['list'] as List? ?? []).cast<Map>()) {
            final conv = 'dm:${idText(item['with']).toLowerCase()}';
            await ensure(sql, org, user, conv);
            await sql.update(
              'UPDATE conversations SET is_archived = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
              [item['archived'] == true ? 1 : 0, org, user, conv],
            );
            if (item['avatar'] != null) {
              await sql.update(
                'UPDATE conversations SET avatar = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
                [idText(item['avatar']), org, user, conv],
              );
            }
            if (item['e2e'] == true) {
              await sql.update(
                'UPDATE conversations SET is_encrypted = 1 WHERE org_id = ? AND user_id = ? AND conv_id = ?',
                [org, user, conv],
              );
            }
            await sql.update(
              'UPDATE conversations SET last_text = ?, last_ts = ?, last_from = ? '
              'WHERE org_id = ? AND user_id = ? AND conv_id = ? AND last_ts <= ?',
              [
                item['e2e'] == true
                    ? '[encrypted message]'
                    : idText(item['text']),
                intOf(item['ts']),
                idText(item['from']),
                org,
                user,
                conv,
                intOf(item['ts']),
              ],
            );
          }
        });
        unawaited(_decryptPreviews((e['list'] as List? ?? []).cast<Map>()));
      case 'groups':
        await _db.transaction((sql) async {
          for (final g in (e['list'] as List? ?? []).cast<Map>()) {
            await _upsertGroup(sql, org, user, g);
          }
        });
      case 'group_created':
      case 'added_to_group':
        await _db.transaction((sql) => _upsertGroup(sql, org, user, e));
      case 'group_system':
        // Not a stored message; the full member list comes from /groups.
        unawaited(_socket.sendCommand('/groups'));
        return;
      case 'left_group':
        await _db.update(
          'UPDATE conversations SET is_archived = 1 WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [org, user, 'group:${idText(e['text'])}'],
        );
      case 'hosts':
        await _db.transaction((sql) async {
          for (final h in (e['list'] as List? ?? []).cast<Map>()) {
            if (h['kind'] != 'department') continue;
            await ensure(
              sql,
              org,
              user,
              'host:${idText(h['key'])}',
              title: idText(h['name']),
            );
          }
        });
      default:
        return;
    }
    await reload();
    if ((e['type'] == 'added_to_group' || e['type'] == 'group_created') &&
        ChatThread.isThreadName(idText(e['name']))) {
      _scheduleThreadNames();
    }
    if (e['type'] == 'hosts' && _listsReady?.isCompleted == false) {
      _listsReady!.complete();
    }
  }

  /// Writes a `group_created` or `added_to_group` event at once, so the group
  /// is in the list before the screen opens it.
  Future<void> saveGroup(Map<String, dynamic> e) async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    await _db.transaction((sql) => _upsertGroup(sql, org, user, e));
    await reload();
  }

  /// A group I just made or was added to has no message yet: it is stamped
  /// with the time so it sits at the top of the list instead of the bottom.
  Future<void> _upsertGroup(Sql sql, String org, String user, Map g) async {
    final conv = 'group:${idText(g['name'])}';
    final members = g['members'] is List ? g['members'] as List : const [];
    final isNew =
        g['type'] == 'added_to_group' ||
        (g['type'] == 'group_created' && members.length <= 1);
    await ensure(sql, org, user, conv);
    await sql.update(
      'UPDATE conversations SET is_archived = 0, members_json = ?, '
      "owner = COALESCE(NULLIF(?, ''), owner), "
      'last_ts = CASE WHEN ? = 1 AND last_ts = 0 THEN ? ELSE last_ts END '
      'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [
        jsonEncode(g['members'] ?? []),
        idText(g['owner']),
        isNew ? 1 : 0,
        DateTime.now().millisecondsSinceEpoch,
        org,
        user,
        conv,
      ],
    );
  }
}
