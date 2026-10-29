import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:get/get.dart';

import '../db/app_database.dart';
import '../models/form_submission.dart';
import '../models/ids.dart';
import '../models/outbox_entry.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';

class SubmissionRepository extends GetxService {
  SubmissionRepository(this._db, this._session, this._socket);

  static const couldNotConfirm = "couldn't confirm delivery";

  /// The server remembers a client id for one day; an entry first sent longer
  /// ago than this can no longer be sent safely again.
  static const _cidMemory = Duration(hours: 23);
  static const _kinds = "('form_submit','form_edit')";

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;

  final submissions = <FormSubmission>[].obs;
  bool _isFlushing = false;

  String? get _org => _session.orgId;
  String? get _me => _session.userId;

  @override
  void onInit() {
    super.onInit();
    _socket.onOnline.listen((_) => _onOnline());
    ever(_session.current, (_) => reload());
    reload();
  }

  Future<void> reload() async {
    if (_org == null || _me == null) {
      submissions.clear();
      return;
    }
    final rows = await _db.query(
      'SELECT * FROM form_submissions WHERE org_id = ? AND user_id = ? ORDER BY ts DESC',
      [_org, _me],
    );
    submissions.assignAll(rows.map(FormSubmission.fromRow));
  }

  // ---- offline writes -------------------------------------------------------

  Future<void> submitForm(
    String name,
    Map<String, dynamic> values, {
    String? chat,
  }) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp-$now';
    await _db.transaction((sql) async {
      await sql.insert(
        'INSERT INTO form_submissions(org_id, user_id, submission_id, tstruct, by_user, ts, values_json, sync_state) '
        "VALUES(?,?,?,?,?,?,?,'pending_create')",
        [org, user, tempId, name, user, now, jsonEncode(values)],
      );
      await sql.insert(
        'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts, cid) '
        "VALUES(?,?,?,'form_submit',?,?,'pending',?,?)",
        [
          org,
          user,
          chat ?? '',
          jsonEncode({'name': name, 'values': values, 'chat': chat}),
          tempId,
          now,
          newCid(),
        ],
      );
    });
    await reload();
    unawaited(flush());
  }

  Future<void> editSubmission(String id, Map<String, dynamic> values) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    if (id.startsWith('temp-')) {
      final rows = await _db.query(
        "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND ref_id = ? AND status IN ('pending','failed')",
        [org, user, id],
      );
      if (rows.isEmpty) return;
      final entry = OutboxEntry.fromRow(rows.first);
      await _db.update('UPDATE outbox SET payload_json = ? WHERE id = ?', [
        jsonEncode({...entry.payload, 'values': values}),
        entry.id,
      ]);
    } else {
      await _db.insert(
        'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts, cid) '
        "VALUES(?,?,'','form_edit',?,?,'pending',?,?)",
        [
          org,
          user,
          jsonEncode({'id': id, 'values': values}),
          id,
          DateTime.now().millisecondsSinceEpoch,
          newCid(),
        ],
      );
    }
    await _db.update(
      "UPDATE form_submissions SET values_json = ?, sync_state = CASE WHEN sync_state = 'pending_create' THEN sync_state ELSE 'pending_edit' END "
      'WHERE org_id = ? AND user_id = ? AND submission_id = ?',
      [jsonEncode(values), org, user, id],
    );
    await reload();
    unawaited(flush());
  }

  Future<void> retry(String refId) async {
    await _db.update(
      "UPDATE outbox SET status = 'pending', retry_count = 0, next_attempt_ts = 0, last_error = NULL "
      "WHERE org_id = ? AND user_id = ? AND ref_id = ? AND status = 'failed' AND kind IN $_kinds",
      [_org, _me, refId],
    );
    unawaited(flush());
  }

  // ---- flusher ----------------------------------------------------------------

  Future<void> flush() async {
    if (_isFlushing) return;
    _isFlushing = true;
    try {
      while (_socket.isOnline && _session.hasSession) {
        final sending = await _db.query(
          "SELECT COUNT(*) AS n FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'sending' AND kind IN $_kinds",
          [_org, _me],
        );
        if (intOf(sending.first['n']) > 0) return;
        final rows = await _db.query(
          "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'pending' AND kind IN $_kinds "
          'AND next_attempt_ts <= ? ORDER BY id LIMIT 1',
          [_org, _me, DateTime.now().millisecondsSinceEpoch],
        );
        if (rows.isEmpty) return;
        await _send(OutboxEntry.fromRow(rows.first));
      }
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _send(OutboxEntry entry) async {
    if (_isPastCidMemory(entry)) {
      await _fail(entry, couldNotConfirm);
      return;
    }
    final cid = entry.cid ?? newCid();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.update(
      "UPDATE outbox SET status = 'sending', attempt_ts = ?, retry_count = retry_count + 1, "
      'first_attempt_ts = COALESCE(first_attempt_ts, ?), cid = ? WHERE id = ?',
      [now, now, cid, entry.id],
    );
    try {
      // A repeat of the same cid returns the first answer with
      // `duplicate: true` and saves nothing; that is an ordinary success.
      if (entry.kind == 'form_submit') {
        final data = await _socket.sdCall('tstruct.submit', {
          'name': entry.payload['name'],
          'values': entry.payload['values'],
          if (entry.payload['chat'] != null) 'chat': entry.payload['chat'],
          'cid': cid,
        });
        await _adopt(
          entry,
          (data['submission'] as Map).cast<String, dynamic>(),
          data['recordStatus'],
        );
      } else {
        final data = await _socket.sdCall('submissions.update', {
          'id': entry.payload['id'],
          'values': entry.payload['values'],
          'cid': cid,
        });
        await _adopt(
          entry,
          (data['submission'] as Map).cast<String, dynamic>(),
          null,
        );
      }
    } on SocketCallError catch (e) {
      await _onSendError(entry, e);
    }
  }

  bool _isPastCidMemory(OutboxEntry e) =>
      e.firstAttemptTs != null &&
      DateTime.now().millisecondsSinceEpoch - e.firstAttemptTs! >
          _cidMemory.inMilliseconds;

  Future<void> _onSendError(OutboxEntry entry, SocketCallError e) async {
    // No answer: the save may or may not have happened, and sending the same
    // cid again is safe either way, so it goes back to pending.
    if (e.isConnectionGap) {
      await _setStatus(entry, 'pending');
      return;
    }
    if (e.code == 'in_progress' ||
        e.code == 'rate_limited' ||
        e.code == 'busy') {
      await _db.update(
        "UPDATE outbox SET status = 'pending', next_attempt_ts = ? WHERE id = ?",
        [
          DateTime.now().millisecondsSinceEpoch + 3000 + Random().nextInt(3000),
          entry.id,
        ],
      );
      return;
    }
    await _fail(entry, e.message.isEmpty ? e.code : e.message);
  }

  Future<void> _setStatus(OutboxEntry e, String status) =>
      _db.update('UPDATE outbox SET status = ? WHERE id = ?', [status, e.id]);

  Future<void> _fail(OutboxEntry e, String reason) async {
    await _db.update(
      "UPDATE outbox SET status = 'failed', last_error = ? WHERE id = ?",
      [reason, e.id],
    );
  }

  Future<void> _adopt(
    OutboxEntry entry,
    Map<String, dynamic> submission,
    Object? recordStatus,
  ) async {
    await _db.transaction((sql) async {
      if (entry.kind == 'form_submit') {
        await sql.update(
          'DELETE FROM form_submissions WHERE org_id = ? AND user_id = ? AND submission_id = ?',
          [_org, _me, entry.refId],
        );
      }
      await _upsertServer(
        sql,
        submission,
        force: true,
        recordStatus: recordStatus,
      );
      await sql.update('DELETE FROM outbox WHERE id = ?', [entry.id]);
    });
    await reload();
  }

  Future<void> _upsertServer(
    Sql sql,
    Map<String, dynamic> s, {
    bool force = false,
    Object? recordStatus,
  }) async {
    final id = idText(s['id']);
    final existing = await sql.query(
      'SELECT sync_state FROM form_submissions WHERE org_id = ? AND user_id = ? AND submission_id = ?',
      [_org, _me, id],
    );
    if (!force &&
        existing.isNotEmpty &&
        existing.first['sync_state'] != 'synced') {
      return;
    }
    final status =
        s['status'] ?? (recordStatus == 'pending' ? 'pending' : null);
    await sql.insert(
      'INSERT OR REPLACE INTO form_submissions(org_id, user_id, submission_id, tstruct, by_user, ts, values_json, labels_json, '
      "status, approval_json, edited_ts, sync_state) VALUES(?,?,?,?,?,?,?,?,?,?,?,'synced')",
      [
        _org,
        _me,
        id,
        idText(s['tstruct']),
        idText(s['by']),
        intOf(s['ts']),
        jsonEncode(s['values'] ?? {}),
        s['labels'] == null ? null : jsonEncode(s['labels']),
        status == null ? null : idText(status),
        s['approval'] == null ? null : jsonEncode(s['approval']),
        s['editedTs'] == null ? null : intOf(s['editedTs']),
      ],
    );
  }

  // ---- sync -------------------------------------------------------------------

  Future<void> _onOnline() async {
    final stale = await _db.query(
      "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'sending' AND kind IN $_kinds ORDER BY id",
      [_org, _me],
    );
    for (final row in stale) {
      final entry = OutboxEntry.fromRow(row);
      // A send with no client id (made before ids existed) may already be on
      // the server; it goes to tap-to-retry instead of being sent again.
      await (entry.cid == null || _isPastCidMemory(entry)
          ? _fail(entry, couldNotConfirm)
          : _setStatus(entry, 'pending'));
    }
    await syncFromServer();
    await flush();
  }

  Future<void> syncFromServer() async {
    if (_org == null || _me == null) return;
    var offset = 0;
    try {
      for (var page = 0; page < 5; page++) {
        final data = await _socket.sdCall('submissions.list', {
          'offset': offset,
        });
        final list = ((data['submissions'] as List?) ?? []).cast<Map>();
        await _db.transaction((sql) async {
          for (final s in list) {
            await _upsertServer(sql, s.cast<String, dynamic>());
          }
        });
        if (data['hasMore'] != true || list.isEmpty) break;
        offset += list.length;
      }
    } on SocketCallError catch (_) {}
    await reload();
  }

  Future<Map<String, dynamic>?> definition(String name) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return null;
    if (_socket.isOnline) {
      try {
        final data = await _socket.sdCall('tstruct.get', {'name': name});
        final tstruct = (data['tstruct'] as Map).cast<String, dynamic>();
        await _db.insert(
          'INSERT OR REPLACE INTO form_definitions(org_id, user_id, name, scope, caption, definition_json, fetched_ts) VALUES(?,?,?,?,?,?,?)',
          [
            org,
            user,
            name,
            'global',
            idText(tstruct['caption']),
            jsonEncode(tstruct),
            DateTime.now().millisecondsSinceEpoch,
          ],
        );
        return tstruct;
      } on SocketCallError catch (_) {}
    }
    final rows = await _db.query(
      'SELECT definition_json FROM form_definitions WHERE org_id = ? AND user_id = ? AND name = ?',
      [org, user, name],
    );
    if (rows.isEmpty) return null;
    return (jsonDecode('${rows.first['definition_json']}') as Map)
        .cast<String, dynamic>();
  }

  /// Debug: submits a real test form with a client id, then the same id again
  /// and reports whether the repeat came back as `duplicate: true` with the
  /// same submission and nothing new saved.
  Future<String> debugCidTest(String name, Map<String, dynamic> values) async {
    final cid = newCid();
    Future<Map<String, dynamic>> submit() => _socket.sdCall('tstruct.submit', {
      'name': name,
      'values': values,
      'cid': cid,
    });
    final first = await submit();
    final again = await submit();
    String id(Map<String, dynamic> d) => idText((d['submission'] as Map)['id']);
    return 'cid $cid: first submission ${id(first)} '
        'duplicate=${first['duplicate'] == true}; repeat submission ${id(again)} '
        'duplicate=${again['duplicate'] == true}, '
        '${id(first) == id(again) && again['duplicate'] == true ? 'nothing saved twice' : 'NOT a clean duplicate'}';
  }
}
