import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../db/app_database.dart';
import '../models/conversation.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

class ConversationRepository extends GetxService {
  ConversationRepository(this._db, this._session, this._socket);

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;

  final conversations = <Conversation>[].obs;
  final isLoaded = false.obs;
  final loadError = RxnString();
  Completer<void>? _listsReady;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    ever(_session.current, (_) => reload());
    reload();
  }

  /// Reads the list from SQLite. Each row carries the newest message of its
  /// thread (joined on the newest rowid by ts), so the list can show a
  /// preview of the right kind without a query per row.
  Future<void> reload() async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) {
      conversations.clear();
      isLoaded.value = true;
      return;
    }
    try {
      final rows = await _db.query(
        'SELECT c.*, m.text AS lm_text, m.kind AS lm_kind, m.is_mine AS lm_mine, m.status AS lm_status, '
        'm.is_encrypted_unsupported AS lm_e2e, m.is_deleted AS lm_deleted, m.form_json AS lm_form '
        'FROM conversations c LEFT JOIN messages m ON m.rowid = ('
        'SELECT x.rowid FROM messages x WHERE x.org_id = c.org_id AND x.user_id = c.user_id AND x.conv_id = c.conv_id '
        'ORDER BY x.ts DESC, x.local_seq DESC LIMIT 1) '
        'WHERE c.org_id = ? AND c.user_id = ? ORDER BY c.last_ts DESC',
        [org, user],
      );
      conversations.assignAll(rows.map(Conversation.fromRow));
      loadError.value = null;
    } catch (e) {
      loadError.value = 'Could not read your chats.';
    } finally {
      isLoaded.value = true;
    }
  }

  /// Asks the server for DM threads, groups and hosts and waits until the
  /// last reply (`hosts`) has been written to SQLite.
  Future<void> requestLists() async {
    _listsReady = Completer<void>();
    await _socket.sendCommand('/conversations');
    await _socket.sendCommand('/groups');
    await _socket.sendCommand('/hosts');
    await _listsReady!.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {},
    );
  }

  /// Opening a thread clears its unread count and moves the local "last
  /// opened" marker to its newest server message (by server ts and position,
  /// never by the phone's clock or by comparing ids). Local only: not shared
  /// across devices.
  Future<void> markRead(String convId) async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    await _db.update(
      'UPDATE conversations SET unread = 0, '
      'read_ts = COALESCE((SELECT ts FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? '
      "AND msg_id NOT LIKE 'temp-%' ORDER BY ts DESC, rowid DESC LIMIT 1), read_ts), "
      'read_id = COALESCE((SELECT msg_id FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? '
      "AND msg_id NOT LIKE 'temp-%' ORDER BY ts DESC, rowid DESC LIMIT 1), read_id) "
      'WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [org, user, convId, org, user, convId, org, user, convId],
    );
    await reload();
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

  Future<void> _onEvent(Map<String, dynamic> e) async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    switch (e['type']) {
      case 'conversations':
        await _db.transaction((sql) async {
          for (final item in (e['list'] as List? ?? []).cast<Map>()) {
            final conv = 'dm:${idText(item['with']).toLowerCase()}';
            await ensure(sql, org, user, conv);
            await sql.update(
              'UPDATE conversations SET is_archived = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
              [item['archived'] == true ? 1 : 0, org, user, conv],
            );
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
      case 'groups':
        await _db.transaction((sql) async {
          for (final g in (e['list'] as List? ?? []).cast<Map>()) {
            await _upsertGroup(sql, org, user, g);
          }
        });
      case 'group_created':
      case 'added_to_group':
        await _db.transaction((sql) => _upsertGroup(sql, org, user, e));
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
    if (e['type'] == 'hosts' && _listsReady?.isCompleted == false) {
      _listsReady!.complete();
    }
  }

  Future<void> _upsertGroup(Sql sql, String org, String user, Map g) async {
    final conv = 'group:${idText(g['name'])}';
    await ensure(sql, org, user, conv);
    await sql.update(
      'UPDATE conversations SET is_archived = 0, members_json = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
      [jsonEncode(g['members'] ?? []), org, user, conv],
    );
  }
}
