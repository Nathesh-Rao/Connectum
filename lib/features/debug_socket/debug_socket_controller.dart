import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/routes/app_routes.dart';
import '../../core/routes/conversation_route.dart';
import '../../core/routes/home_reload.dart';
import '../../data/api/api_client.dart';
import '../../data/db/app_database.dart';
import '../../data/models/conversation.dart';
import '../../data/models/ids.dart';
import '../../data/redact.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../data/repositories/presence_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/submission_repository.dart';
import '../../data/socket/connectivity_service.dart';
import '../../data/socket/socket_service.dart';

class DebugSocketController extends GetxController {
  DebugSocketController({
    required this.socket,
    required this.connectivity,
    required this.session,
    required this.messages,
    required this.conversationRepository,
    required this.submissions,
    required this.presence,
    required AppDatabase db,
  }) : _db = db;

  final SocketService socket;
  final ConnectivityService connectivity;
  final SessionRepository session;
  final MessageRepository messages;
  final ConversationRepository conversationRepository;
  final SubmissionRepository submissions;
  final PresenceRepository presence;
  final AppDatabase _db;

  final orgId = TextEditingController();
  final username = TextEditingController();
  final token = TextEditingController();
  final identityToken = TextEditingController();
  final enterpriseId = TextEditingController();
  final convId = TextEditingController(text: 'dm:');
  final messageText = TextEditingController(text: 'test message');
  final sdAction = TextEditingController(text: 'users.search');
  final sdArgs = TextEditingController(text: '{"q":""}');
  final upTo = TextEditingController(text: '1');
  final formName = TextEditingController();
  final formValues = TextEditingController(text: '{}');

  final notes = <String>[].obs;
  final outbox = ''.obs;
  final lastCid = '-'.obs;
  final recent = ''.obs;
  Timer? _timer;
  StreamSubscription<Map<String, dynamic>>? _acks;
  String? _cidConv;
  String? _cidText;

  @override
  void onInit() {
    super.onInit();
    _refreshOutbox();
    _acks = socket.events.listen(_noteAck);
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshOutbox(),
    );
  }

  Future<void> _refreshOutbox() async {
    final rows = await _db.query(
      'SELECT kind, status, COUNT(*) AS n FROM outbox GROUP BY kind, status',
    );
    outbox.value = rows.isEmpty
        ? 'empty'
        : rows.map((r) => '${r['kind']}/${r['status']}: ${r['n']}').join('  ');
  }

  void _note(String line) {
    notes.insert(0, line);
    if (notes.length > 10) notes.removeRange(10, notes.length);
  }

  void connect() => socket.start();

  void disconnect() => socket.stop();

  Future<void> loginDirect() async {
    await session.signIn(
      orgId: orgId.text.trim(),
      userId: username.text.trim(),
      token: token.text.trim(),
    );
    token.clear();
    _note('signed in (token stored, not shown)');
  }

  Future<void> enterFlow() async {
    try {
      final shape = await session.enter(
        identityToken.text.trim(),
        enterpriseId.text.trim(),
      );
      identityToken.clear();
      _note('enter ok, shape: $shape');
    } on ApiException catch (e) {
      _note('enter failed: ${e.code} (${e.status})');
    }
  }

  Future<void> sendTest() async {
    final result = await messages.sendText(
      convId.text.trim(),
      messageText.text,
    );
    _note('send ${convId.text.trim()}: ${result.name}');
    await _refreshOutbox();
  }

  void _noteAck(Map<String, dynamic> e) {
    final type = idText(e['type']);
    if (e['cid'] != null && type.endsWith('ack')) {
      _note(
        '$type cid=${e['cid']} id=${e['id']} duplicate=${e['duplicate'] == true}',
      );
    } else if (type == 'error' && e['code'] != null) {
      _note('error code=${e['code']}');
    }
  }

  Future<void> sendWithCid() async {
    _cidConv = convId.text.trim();
    _cidText = messageText.text;
    lastCid.value = newCid();
    await _sendCid();
  }

  Future<void> sendSameCidAgain() async {
    if (_cidConv == null) {
      _note('send with a cid first');
      return;
    }
    await _sendCid();
  }

  Future<void> _sendCid() async {
    final command = MessageRepository.cidCommand(
      _cidConv!,
      _cidText!,
      lastCid.value,
    );
    if (command == null) {
      _note('a client id works for dm:, group: and host: only');
      return;
    }
    final sent = await socket.sendCommand(command);
    _note('sent $_cidConv cid=${lastCid.value}${sent ? '' : ' (offline)'}');
  }

  Future<void> loadOlder(String conv) async {
    final page = await messages.loadOlder(conv);
    if (page == null) {
      _note('older $conv: no answer (offline or nothing stored)');
      return;
    }
    _note(
      'older $conv: ${page.count} messages, hasMore=${page.hasMore}, next=${page.next}',
    );
  }

  Future<void> showMessages() async {
    final rows = await _db.query(
      'SELECT msg_id, cid, status, is_encrypted_unsupported AS e2e, text FROM messages '
      'WHERE org_id = ? AND user_id = ? AND conv_id = ? ORDER BY ts DESC, local_seq DESC LIMIT 8',
      [session.store.orgId, session.store.userId, convId.text.trim()],
    );
    recent.value = rows.isEmpty
        ? 'no stored messages'
        : rows
              .map(
                (r) =>
                    '${r['msg_id']}  ${r['status']}  cid=${r['cid'] ?? '-'}  e2e=${intOf(r['e2e']) == 1}  ${idText(r['text']).length}ch',
              )
              .join('\n');
  }

  /// Runs one `/sd` action and notes the answer as redacted JSON (long text
  /// is cut). For checking a response shape against the real server.
  Future<void> runSd() async {
    try {
      final args = (jsonDecode(sdArgs.text) as Map).cast<String, dynamic>();
      final data = await socket.sdCall(sdAction.text.trim(), args);
      _note('${sdAction.text.trim()}: ${jsonEncode(Redact.value(data))}');
    } on SocketCallError catch (e) {
      _note('${sdAction.text.trim()} failed: ${e.code} ${e.message}');
    } on FormatException catch (_) {
      _note('args must be a JSON object');
    }
  }

  // ---- inbox state, read, delivered, pin, mute -----------------------------

  Future<void> convListFull() async {
    try {
      final data = await socket.sdCall('conv.list', {'full': true});
      _note('conv.list full: ${jsonEncode(Redact.value(data))}');
    } on SocketCallError catch (e) {
      _note('conv.list failed: ${e.code} ${e.message}');
    }
  }

  Future<void> showInboxState() async {
    final rows = await _db.query(
      'SELECT conv_id, unread, unread_more, last_id, read_id, delivered_id, peer_read_id, peer_delivered_id, '
      'is_pinned, is_muted, is_archived, pending_read_id, pending_delivered_id FROM conversations '
      'WHERE org_id = ? AND user_id = ?',
      [session.store.orgId, session.store.userId],
    );
    _note(
      rows.isEmpty
          ? 'no conversations stored'
          : rows.map((r) => jsonEncode(r)).join('\n'),
    );
  }

  Future<void> markReadDebug() async {
    await conversationRepository.markRead(convId.text.trim(), upTo.text.trim());
    _note(
      'markRead ${convId.text.trim()} up to ${upTo.text.trim()} (local zero now, sent debounced)',
    );
  }

  Future<void> deliveredDebug() async {
    await conversationRepository.noteDelivered(
      convId.text.trim(),
      upTo.text.trim(),
    );
    _note(
      'delivered ${convId.text.trim()} up to ${upTo.text.trim()} (sent debounced)',
    );
  }

  Conversation? _selected() {
    for (final c in conversationRepository.conversations) {
      if (c.convId == convId.text.trim()) return c;
    }
    _note('no stored conversation ${convId.text.trim()}');
    return null;
  }

  Future<void> togglePin() async {
    final c = _selected();
    if (c == null) return;
    try {
      await conversationRepository.setPinned(c.convId, isPinned: !c.isPinned);
      _note('${c.convId} pinned: ${!c.isPinned}');
    } on SocketCallError catch (e) {
      _note('pin failed: ${e.code} ${e.message}');
    }
  }

  Future<void> toggleMute() async {
    final c = _selected();
    if (c == null) return;
    try {
      await conversationRepository.setMuted(c.convId, isMuted: !c.isMuted);
      _note('${c.convId} muted: ${!c.isMuted}');
    } on SocketCallError catch (e) {
      _note('mute failed: ${e.code} ${e.message}');
    }
  }

  Future<void> readersDebug() async {
    try {
      final data = await conversationRepository.readers(
        convId.text.trim(),
        upTo.text.trim(),
      );
      _note('conv.readers: ${jsonEncode(Redact.value(data))}');
    } on SocketCallError catch (e) {
      _note('conv.readers failed: ${e.code} ${e.message}');
    }
  }

  Future<void> fakeReceipt(String kind) async {
    _note(
      'fake $kind receipt up to ${upTo.text.trim()}: '
      '${await messages.debugReceipt(convId.text.trim(), kind, upTo.text.trim())}',
    );
  }

  Future<void> fakeIncoming() async {
    final base = int.tryParse(upTo.text.trim()) ?? 9200;
    _note(
      await messages.debugIncoming(convId.text.trim(), [
        '${base + 1}',
        '${base + 1}',
        '$base',
        '${base + 2}',
        'x-not-a-number',
      ]),
    );
  }

  Future<void> presenceList() async {
    await presence.refresh();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    _note(
      'presence known=${presence.isKnown.value}: ${presence.online.toList()}',
    );
  }

  Future<void> syncNow() async {
    _note('sync started');
    await messages.syncNow();
    await submissions.syncFromServer();
    _note('sync finished');
  }

  Future<void> cidTest() async {
    try {
      final values = (jsonDecode(formValues.text) as Map)
          .cast<String, dynamic>();
      _note(await submissions.debugCidTest(formName.text.trim(), values));
    } on SocketCallError catch (e) {
      _note('cid test failed: ${e.code} ${e.message}');
    } on FormatException catch (_) {
      _note('form values must be a JSON object');
    }
  }

  /// Migration check: writes a few rows with the columns every version has
  /// (a thread, messages, a pending outbox row that is never due), so an
  /// upgrade of the database can be checked against real rows.
  Future<void> seedMigrationRows() async {
    final org = session.store.orgId;
    final user = session.store.userId;
    if (org == null || user == null) {
      _note('sign in first');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction((sql) async {
      await sql.update(
        'DELETE FROM conversations WHERE org_id = ? AND user_id = ? AND conv_id LIKE ?',
        [org, user, '%migtest%'],
      );
      await sql.update(
        'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND conv_id LIKE ?',
        [org, user, '%migtest%'],
      );
      await sql.update(
        'DELETE FROM outbox WHERE org_id = ? AND user_id = ? AND conv_id LIKE ?',
        [org, user, '%migtest%'],
      );
      await sql.insert(
        'INSERT INTO conversations(org_id, user_id, conv_id, kind, title, last_text, last_ts, last_from, unread) '
        'VALUES(?,?,?,?,?,?,?,?,?)',
        [org, user, 'dm:migtest', 'dm', 'migtest', 'third', now, 'migtest', 2],
      );
      for (var i = 1; i <= 3; i++) {
        await sql.insert(
          'INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, text, ts, status) '
          'VALUES(?,?,?,?,?,?,?,?,?)',
          [
            org,
            user,
            '900$i',
            'dm:migtest',
            'migtest',
            0,
            'msg $i',
            now - (4 - i) * 1000,
            'sent',
          ],
        );
      }
      await sql.insert(
        'INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, text, ts, status, cid) '
        'VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          org,
          user,
          'temp-$now',
          'dm:migtest',
          user,
          1,
          'waiting',
          now,
          'pending',
          'm-migtest-1',
        ],
      );
      for (final id in ['9101', '9102', 'abc']) {
        await sql.insert(
          'INSERT INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, text, ts, status) '
          'VALUES(?,?,?,?,?,?,?,?,?)',
          [org, user, id, 'dm:migtest', user, 1, 'mine $id', now - 500, 'sent'],
        );
      }
      await sql.insert(
        'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, next_attempt_ts, created_ts, cid) '
        'VALUES(?,?,?,?,?,?,?,?,?,?)',
        [
          org,
          user,
          'dm:migtest',
          'message',
          jsonEncode({'text': 'waiting'}),
          'temp-$now',
          'pending',
          4102444800000,
          now,
          'm-migtest-1',
        ],
      );
    });
    _note('seeded migration rows (an outbox row that is never due)');
    await countRows();
  }

  /// Every outbox row of this account, with message text cut to its length,
  /// and how many rows each table holds for this account.
  Future<void> showOutboxRows() async {
    final org = session.store.orgId;
    final user = session.store.userId;
    final rows = await _db.query(
      'SELECT id, conv_id, kind, status, created_ts, next_attempt_ts, retry_count, ref_id, cid, payload_json '
      'FROM outbox WHERE org_id = ? AND user_id = ? ORDER BY id',
      [org, user],
    );
    String payload(Object? json) {
      try {
        final m = jsonDecode('$json');
        if (m is! Map) return '?';
        return jsonEncode({
          for (final e in m.entries)
            e.key: e.value is String && e.key == 'text'
                ? '<${(e.value as String).length} chars>'
                : e.value is Map || e.value is List
                ? '<${e.value.runtimeType}>'
                : e.value,
        });
      } catch (_) {
        return 'unreadable';
      }
    }

    String time(Object? ms) => ms == null
        ? '-'
        : DateTime.fromMillisecondsSinceEpoch(intOf(ms)).toIso8601String();
    _note(
      rows.isEmpty
          ? 'outbox: no rows'
          : rows
                .map(
                  (r) =>
                      'outbox row ${r['id']}: conv=${r['conv_id']} kind=${r['kind']} status=${r['status']} '
                      'created=${time(r['created_ts'])} nextAttempt=${time(r['next_attempt_ts'])} '
                      'retries=${r['retry_count']} ref=${r['ref_id']} cid=${r['cid']} payload=${payload(r['payload_json'])}',
                )
                .join('\n'),
    );
    Future<int> n(String table, [String where = '']) async => intOf(
      (await _db.query(
        'SELECT COUNT(*) AS n FROM $table WHERE org_id = ? AND user_id = ? $where',
        [org, user],
      )).first['n'],
    );
    _note(
      'counts for $user: conversations ${await n('conversations')}, messages ${await n('messages')}, '
      'outbox ${await n('outbox')}, sync_cursor ${await n('sync_cursor')}, form_submissions ${await n('form_submissions')}, '
      'form_definitions ${await n('form_definitions')}; rows of the test conversation: '
      'conversations ${await n('conversations', "AND conv_id = 'dm:migtest'")}, '
      'messages ${await n('messages', "AND conv_id = 'dm:migtest'")}, '
      'outbox ${await n('outbox', "AND conv_id = 'dm:migtest'")}, '
      'sync_cursor ${await n('sync_cursor', "AND conv_id = 'dm:migtest'")}',
    );
  }

  /// Removes the rows the migration test made, and nothing else: everything of
  /// the one test conversation `dm:migtest`. It refuses to run if the outbox
  /// holds any row that is not the seeded one.
  Future<void> removeTestRows() async {
    final org = session.store.orgId;
    final user = session.store.userId;
    final outboxRows = await _db.query(
      'SELECT id, conv_id, cid FROM outbox WHERE org_id = ? AND user_id = ?',
      [org, user],
    );
    final others = outboxRows.where(
      (r) => r['conv_id'] != 'dm:migtest' || r['cid'] != 'm-migtest-1',
    );
    if (others.isNotEmpty) {
      _note(
        'not removed: outbox row(s) ${others.map((r) => r['id']).join(', ')} are not the seeded one',
      );
      return;
    }
    await _db.transaction((sql) async {
      for (final table in [
        'outbox',
        'messages',
        'conversations',
        'sync_cursor',
      ]) {
        await sql.update(
          "DELETE FROM $table WHERE org_id = ? AND user_id = ? AND conv_id = 'dm:migtest'",
          [org, user],
        );
      }
    });
    _note('removed the test conversation dm:migtest and its rows');
    await showOutboxRows();
  }

  Future<void> countRows() async {
    final org = session.store.orgId;
    final user = session.store.userId;
    final version = await _db.query('PRAGMA user_version');
    Future<int> count(String table, [String where = '']) async {
      final rows = await _db.query(
        'SELECT COUNT(*) AS n FROM $table WHERE org_id = ? AND user_id = ? $where',
        [org, user],
      );
      return intOf(rows.first['n']);
    }

    final pending = await count(
      'outbox',
      "AND status = 'pending' AND conv_id LIKE '%migtest%'",
    );
    _note(
      'database version ${version.first.values.first}: '
      'conversations ${await count('conversations')}, '
      'messages ${await count('messages')}, '
      'outbox ${await count('outbox')} (migtest pending: $pending), '
      'migtest messages ${await count('messages', "AND conv_id LIKE '%migtest%'")}',
    );
  }

  /// Opens Chats, then after a pause (to set a state up there: keyboard,
  /// menu, switcher sheet, scroll) runs the same navigation a real enterprise
  /// switch ends with. It never calls `enter` and never touches the session.
  Future<void> simulateSwitchReload() async {
    _note('Chats opens now; the reload runs in 8 s');
    unawaited(Get.toNamed(AppRoutes.chats));
    await Future<void>.delayed(const Duration(seconds: 8));
    await HomeReload.run();
  }

  /// Conversation A, then conversation B pushed over it, to check that each
  /// has its own controller (go back to A afterwards and use it).
  Future<void> openStacked() async {
    ConversationRoute.open('dm:priya');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    ConversationRoute.open('dm:arjun');
  }

  /// A conversation on screen, then the switch reload.
  Future<void> reloadWithConversation() async {
    ConversationRoute.open('dm:priya');
    await Future<void>.delayed(const Duration(seconds: 6));
    await HomeReload.run();
  }

  Future<void> signOut() => session.signOut();

  @override
  void onClose() {
    _timer?.cancel();
    _acks?.cancel();
    for (final c in [
      orgId,
      username,
      token,
      identityToken,
      enterpriseId,
      convId,
      messageText,
      formName,
      formValues,
      upTo,
      sdAction,
      sdArgs,
    ]) {
      c.dispose();
    }
    super.onClose();
  }
}
