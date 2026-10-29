import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import '../../core/debug/seed_ui.dart';
import '../db/app_database.dart';
import '../models/form_card.dart';
import '../models/form_entry.dart';
import '../models/form_definition.dart';
import '../models/form_submission.dart';
import '../models/ids.dart';
import '../models/message.dart';
import '../models/outbox_entry.dart';
import '../session_store.dart';
import 'message_repository.dart';
import '../socket/socket_service.dart';

class SubmissionRepository extends GetxService {
  SubmissionRepository(this._db, this._session, this._socket, this._messages);

  static const couldNotConfirm = "couldn't confirm delivery";
  static const invalidReason = 'Some answers need fixing.';

  /// The server remembers a client id for one day; an entry first sent longer
  /// ago than this can no longer be sent safely again.
  static const _cidMemory = Duration(hours: 23);
  static const _kinds = "('form_submit','form_edit','form_resubmit')";

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final MessageRepository _messages;

  /// A plain-words problem with a save that happened in the background (an
  /// edit that was refused); the open screen shows it once.
  final notice = RxnString();

  final submissions = <FormSubmission>[].obs;

  /// The forms the cached submissions belong to, by form name: full ones where
  /// a definition was fetched, captions only otherwise.
  final definitions = <String, FormDefinition>{}.obs;
  final isLoaded = false.obs;

  /// Saves that never reached the server and won't on their own: the local id
  /// of each and the plain reason. A card shows them as failed.
  final failures = <String, String>{}.obs;
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
    if (SeedUi.isActive) {
      definitions.assignAll(SeedUi.definitions());
      submissions.assignAll(SeedUi.submissions());
      isLoaded.value = true;
      return;
    }
    if (_org == null || _me == null) {
      submissions.clear();
      definitions.clear();
      return;
    }
    final defs = await _db.query(
      'SELECT name, scope, definition_json FROM form_definitions WHERE org_id = ? AND user_id = ?',
      [_org, _me],
    );
    final rows = await _db.query(
      'SELECT * FROM form_submissions WHERE org_id = ? AND user_id = ? ORDER BY ts DESC',
      [_org, _me],
    );
    definitions.assignAll({
      for (final d in defs)
        idText(d['name']): FormDefinition.parse(
          idText(d['name']),
          idText(d['scope']),
          idText(d['definition_json']),
        ),
    });
    submissions.assignAll(rows.map(FormSubmission.fromRow));
    final failed = await _db.query(
      "SELECT ref_id, last_error FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'failed' AND kind = 'form_submit'",
      [_org, _me],
    );
    failures.assignAll({
      for (final f in failed) idText(f['ref_id']): idText(f['last_error']),
    });
    isLoaded.value = true;
  }

  FormSubmission? submissionById(String id) {
    for (final s in submissions) {
      if (s.submissionId == id) return s;
    }
    return null;
  }

  /// One submission for a card or the detail page. A submission of mine comes
  /// from the cache (it has the grid sections); anyone else's comes from the
  /// form message it was shared in, when that is given.
  Future<FormCardData?> cardFor(
    String id, {
    String? convId,
    String? msgId,
  }) async {
    final mine = submissionById(id);
    if (mine != null) {
      return FormCardData.fromSubmission(mine, definition: definitions[mine.tstruct]);
    }
    if (convId == null || msgId == null) return null;
    Message? message;
    if (SeedUi.isActive) {
      for (final m in SeedMessages.of(convId)) {
        if (m.msgId == msgId) message = m;
      }
    } else if (_org != null && _me != null) {
      final rows = await _db.query(
        'SELECT * FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
        [_org, _me, convId, msgId],
      );
      if (rows.isNotEmpty) message = Message.fromRow(rows.first);
    }
    if (message == null) return null;
    final card = FormCardData.fromMessage(message);
    if (card == null) return null;
    return FormCardData.fromMessage(
      message,
      definition: definitions[card.structure],
    );
  }

  // ---- offline writes -------------------------------------------------------

  /// Saves a new submission and its outbox entry in one step, so a crash
  /// leaves both or neither. From a conversation, a pending form message is
  /// written into it too (the card shows at once, clock and dimmed). [cid]
  /// is the one id of this save: asking twice with it changes nothing.
  Future<void> submitForm(
    String name,
    Map<String, dynamic> values, {
    required String cid,
    String scope = '',
    String caption = '',
    String? chat,
  }) async {
    if (SeedUi.isActive) {
      _seedSubmit(name, values, caption: caption, chat: chat);
      return;
    }
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final known = await _db.query(
      'SELECT 1 FROM outbox WHERE org_id = ? AND user_id = ? AND cid = ?',
      [org, user, cid],
    );
    if (known.isNotEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp-$now';
    final def = definitions[name];
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
          jsonEncode({
            'name': name,
            'scope': scope.isNotEmpty ? scope : def?.scope ?? '',
            'caption': caption.isNotEmpty ? caption : def?.caption ?? '',
            'values': values,
            'chat': chat,
          }),
          tempId,
          now,
          cid,
        ],
      );
      if (chat != null) {
        await _putPendingMessage(sql, tempId, chat, name, caption, values, now, cid: cid);
      }
    });
    await reload();
    if (chat != null) await _messages.reloadAfterLocalChange();
    unawaited(flush());
  }

  Future<void> _putPendingMessage(
    Sql sql,
    String tempId,
    String chat,
    String name,
    String caption,
    Map<String, dynamic> values,
    int ts, {
    required String cid,
    bool isReplace = false,
  }) async {
    final json = pendingFormJson(
      tempId,
      name,
      caption,
      values,
      definitions[name],
      _me ?? '',
    );
    if (isReplace) {
      await sql.update(
        "UPDATE messages SET form_json = ?, status = 'pending', fail_reason = NULL "
        'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [json, _org, _me, tempId],
      );
      return;
    }
    await sql.insert(
      'INSERT OR REPLACE INTO messages(org_id, user_id, msg_id, conv_id, sender, is_mine, kind, text, ts, status, form_json, cid, local_seq) '
      "VALUES(?,?,?,?,?,1,'form',?,?,'pending',?,?,?)",
      [
        _org,
        _me,
        tempId,
        chat,
        _me,
        '${caption.isEmpty ? name : caption} submitted',
        ts,
        json,
        cid,
        ts,
      ],
    );
  }

  /// The form document a card is built from, as a form message carries it:
  /// the fields in the form's order with their shown values. Grid sections
  /// are left out, as the server leaves them out of a form message.
  static String pendingFormJson(
    String id,
    String name,
    String caption,
    Map<String, dynamic> values,
    FormDefinition? def,
    String by,
  ) {
    final fields = <Map<String, dynamic>>[];
    final order = [
      if (def != null)
        for (final f in def.fields)
          if (!def.isGridSection(f.section) && values.containsKey(f.name)) f.name,
      for (final k in values.keys)
        if (!(def?.fieldOf(k) != null) && values[k] is! List) k,
    ];
    for (final k in order.toSet()) {
      final v = values[k];
      if (v is List && v.isNotEmpty && v.first is Map) continue;
      fields.add({
        'name': k,
        'caption': def?.captionOf(k) ?? FormEntry.humanize(k),
        'value': v,
      });
    }
    return jsonEncode({
      'structure': name,
      'scope': def?.scope ?? '',
      'caption': caption.isNotEmpty
          ? caption
          : (def?.caption.isNotEmpty ?? false)
          ? def!.caption
          : name,
      'submissionId': id,
      'by': by,
      'fields': fields,
    });
  }

  /// An edit of a saved submission, sent as `submissions.update`.
  Future<void> editSubmission(
    String id,
    Map<String, dynamic> values, {
    required String cid,
  }) async {
    if (SeedUi.isActive) {
      _seedEdit(id, values);
      return;
    }
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    if (id.startsWith('temp-')) {
      await resendFailed(id, values);
      return;
    }
    await _queueSaved('form_edit', id, values, cid);
  }

  /// A declined submission fixed and sent again (`submission.resubmit`).
  Future<void> resubmit(
    String id,
    Map<String, dynamic> values, {
    required String cid,
  }) async {
    if (SeedUi.isActive) {
      _seedEdit(id, values);
      return;
    }
    await _queueSaved('form_resubmit', id, values, cid);
  }

  Future<void> _queueSaved(
    String kind,
    String id,
    Map<String, dynamic> values,
    String cid,
  ) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final known = await _db.query(
      'SELECT 1 FROM outbox WHERE org_id = ? AND user_id = ? AND cid = ?',
      [org, user, cid],
    );
    if (known.isNotEmpty) return;
    await _db.transaction((sql) async {
      await sql.insert(
        'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts, cid) '
        "VALUES(?,?,'',?,?,?,'pending',?,?)",
        [
          org,
          user,
          kind,
          jsonEncode({'id': id, 'values': values}),
          id,
          DateTime.now().millisecondsSinceEpoch,
          cid,
        ],
      );
      await sql.update(
        "UPDATE form_submissions SET values_json = ?, sync_state = 'pending_edit' "
        'WHERE org_id = ? AND user_id = ? AND submission_id = ?',
        [jsonEncode(values), org, user, id],
      );
    });
    await reload();
    unawaited(flush());
  }

  /// Fixes a submission that never reached the server (it was refused, or
  /// still waits): the entry keeps its place and its id and is sent again.
  Future<void> resendFailed(String refId, Map<String, dynamic> values) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final rows = await _db.query(
      "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND ref_id = ? AND kind = 'form_submit' AND status IN ('pending','failed')",
      [org, user, refId],
    );
    if (rows.isEmpty) return;
    final entry = OutboxEntry.fromRow(rows.first);
    final payload = {...entry.payload, 'values': values}..remove('errors');
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET payload_json = ?, status = 'pending', retry_count = 0, next_attempt_ts = 0, "
        'last_error = NULL, first_attempt_ts = NULL WHERE id = ?',
        [jsonEncode(payload), entry.id],
      );
      await sql.update(
        'UPDATE form_submissions SET values_json = ? WHERE org_id = ? AND user_id = ? AND submission_id = ?',
        [jsonEncode(values), org, user, refId],
      );
      final chat = payload['chat'];
      if (chat is String) {
        await _putPendingMessage(
          sql,
          refId,
          chat,
          idText(payload['name']),
          idText(payload['caption']),
          values,
          entry.createdTs,
          cid: entry.cid ?? '',
          isReplace: true,
        );
      }
    });
    await reload();
    await _messages.reloadAfterLocalChange();
    unawaited(flush());
  }

  /// What a failed or waiting submission was filled in with, and the server's
  /// complaint about it, for "Edit and resend".
  Future<({Map<String, dynamic> values, Object? errors, String name, String scope, String caption})?>
  pendingFor(String refId) async {
    final rows = await _db.query(
      "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND ref_id = ? AND kind = 'form_submit'",
      [_org, _me, refId],
    );
    if (rows.isEmpty) return null;
    final p = OutboxEntry.fromRow(rows.first).payload;
    return (
      values: ((p['values'] as Map?) ?? {}).cast<String, dynamic>(),
      errors: p['errors'],
      name: idText(p['name']),
      scope: idText(p['scope']),
      caption: idText(p['caption']),
    );
  }

  Future<void> retry(String refId) async {
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET status = 'pending', retry_count = 0, next_attempt_ts = 0, last_error = NULL, first_attempt_ts = NULL "
        "WHERE org_id = ? AND user_id = ? AND ref_id = ? AND status = 'failed' AND kind IN $_kinds",
        [_org, _me, refId],
      );
      await sql.update(
        "UPDATE messages SET status = 'pending', fail_reason = NULL WHERE org_id = ? AND user_id = ? AND msg_id = ? AND status = 'failed'",
        [_org, _me, refId],
      );
    });
    await _messages.reloadAfterLocalChange();
    unawaited(flush());
  }

  /// Drops a submission that was never sent: its entry, its row and its card.
  Future<void> discardPending(String refId) async {
    if (SeedUi.isActive) return;
    await _db.transaction((sql) async {
      for (final table in ['outbox', 'form_submissions', 'messages']) {
        final column = switch (table) {
          'outbox' => 'ref_id',
          'form_submissions' => 'submission_id',
          _ => 'msg_id',
        };
        await sql.update(
          'DELETE FROM $table WHERE org_id = ? AND user_id = ? AND $column = ?',
          [_org, _me, refId],
        );
      }
    });
    await reload();
    await _messages.reloadAfterLocalChange();
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
        if (rows.isEmpty) {
          await _scheduleWake();
          return;
        }
        await _send(OutboxEntry.fromRow(rows.first));
      }
    } finally {
      _isFlushing = false;
    }
  }

  Timer? _wakeTimer;

  Future<void> _scheduleWake() async {
    final rows = await _db.query(
      "SELECT MIN(next_attempt_ts) AS t FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'pending' "
      'AND kind IN $_kinds AND next_attempt_ts > ?',
      [_org, _me, DateTime.now().millisecondsSinceEpoch],
    );
    final next = rows.first['t'];
    if (next == null) return;
    _wakeTimer?.cancel();
    final wait = intOf(next) - DateTime.now().millisecondsSinceEpoch;
    _wakeTimer = Timer(Duration(milliseconds: wait + 50), flush);
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
    await _setMessageStatus(entry, 'sending');
    try {
      // A repeat of the same cid returns the first answer with
      // `duplicate: true` and saves nothing; that is an ordinary success.
      if (entry.kind == 'form_submit') {
        final name = idText(entry.payload['name']);
        final scope = idText(entry.payload['scope']).isNotEmpty
            ? idText(entry.payload['scope'])
            : definitions[name]?.scope ?? '';
        final data = await _socket.sdCall(
          scope == 'user' ? 'tstruct.user.submit' : 'tstruct.submit',
          {
            'name': name,
            'values': entry.payload['values'],
            if (entry.payload['chat'] != null) 'chat': entry.payload['chat'],
            'cid': cid,
          },
        );
        await _adopt(
          entry,
          (data['submission'] as Map).cast<String, dynamic>(),
          data['recordStatus'],
          message: data['message'] is Map
              ? (data['message'] as Map).cast<String, dynamic>()
              : null,
        );
      } else {
        final data = await _socket.sdCall(
          entry.kind == 'form_resubmit'
              ? 'submission.resubmit'
              : 'submissions.update',
          {
            'id': entry.payload['id'] is num
                ? entry.payload['id']
                : int.tryParse(idText(entry.payload['id'])) ??
                      entry.payload['id'],
            'values': entry.payload['values'],
            'cid': cid,
          },
        );
        await _adopt(
          entry,
          (data['submission'] as Map).cast<String, dynamic>(),
          data['recordStatus'],
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
      await _setMessageStatus(entry, 'pending');
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
      await _setMessageStatus(entry, 'pending');
      return;
    }
    if (e.code == 'invalid_values' && entry.kind == 'form_submit') {
      await _db.update('UPDATE outbox SET payload_json = ? WHERE id = ?', [
        jsonEncode({...entry.payload, 'errors': e.details}),
        entry.id,
      ]);
    }
    await _fail(entry, _plainReason(e));
  }

  static String _plainReason(SocketCallError e) {
    if (e.code == 'invalid_values') return invalidReason;
    if (e.code == 'submission_locked') {
      return "It can't be changed while it waits for approval.";
    }
    if (e.code == 'forbidden') return "You can't use this form.";
    return e.message.isEmpty ? e.code : e.message;
  }

  Future<void> _setStatus(OutboxEntry e, String status) =>
      _db.update('UPDATE outbox SET status = ? WHERE id = ?', [status, e.id]);

  Future<void> _fail(OutboxEntry e, String reason) async {
    await _db.update(
      "UPDATE outbox SET status = 'failed', last_error = ? WHERE id = ?",
      [reason, e.id],
    );
    await _setMessageStatus(e, 'failed', reason: reason);
    if (e.kind == 'form_submit') unawaited(reload());
    if (e.kind != 'form_submit') {
      // A refused edit leaves the server's version in place.
      await _db.update(
        "UPDATE form_submissions SET sync_state = 'synced' WHERE org_id = ? AND user_id = ? AND submission_id = ? AND sync_state = 'pending_edit'",
        [_org, _me, e.refId],
      );
      notice.value = reason == couldNotConfirm
          ? "An edit couldn't be confirmed. Check the submission."
          : 'An edit was not saved: $reason';
      unawaited(syncFromServer());
    }
  }

  /// The card in the conversation follows its entry: waiting, sending,
  /// failed (with the reason).
  Future<void> _setMessageStatus(
    OutboxEntry e,
    String status, {
    String? reason,
  }) async {
    if (e.kind != 'form_submit' || idText(e.payload['chat']).isEmpty) return;
    await _db.update(
      'UPDATE messages SET status = ?, fail_reason = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [status, reason, _org, _me, e.refId],
    );
    await _messages.reloadAfterLocalChange();
  }

  Future<void> _adopt(
    OutboxEntry entry,
    Map<String, dynamic> submission,
    Object? recordStatus, {
    Map<String, dynamic>? message,
  }) async {
    final chat = idText(entry.payload['chat']);
    await _db.transaction((sql) async {
      if (entry.kind == 'form_submit') {
        await sql.update(
          'DELETE FROM form_submissions WHERE org_id = ? AND user_id = ? AND submission_id = ?',
          [_org, _me, entry.refId],
        );
        if (chat.isNotEmpty) {
          await _settleMessage(
            sql,
            entry,
            idText(submission['id']),
            message,
            isWaiting: recordStatus == 'pending',
          );
        }
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
    if (chat.isNotEmpty) await _messages.reloadAfterLocalChange();
  }

  /// The pending card takes the server's message id and time. If the live
  /// event got there first, the temp card just goes. A submission waiting for
  /// approval has no message yet: the card stays, and goes when the real one
  /// is posted.
  Future<void> _settleMessage(
    Sql sql,
    OutboxEntry entry,
    String submissionId,
    Map<String, dynamic>? message, {
    required bool isWaiting,
  }) async {
    final serverId = message == null ? '' : idText(message['id']);
    if (serverId.isNotEmpty) {
      final exists = await sql.query(
        'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [_org, _me, serverId],
      );
      if (exists.isNotEmpty) {
        await sql.update(
          'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [_org, _me, entry.refId],
        );
      } else {
        await sql.update(
          "UPDATE messages SET msg_id = ?, ts = COALESCE(?, ts), status = 'sent', fail_reason = NULL, local_seq = 0, "
          'form_json = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [
            serverId,
            message!['ts'] == null ? null : intOf(message['ts']),
            _withSubmissionId(entry, submissionId),
            _org,
            _me,
            entry.refId,
          ],
        );
      }
    } else if (isWaiting) {
      await sql.update(
        "UPDATE messages SET status = 'sent', form_json = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?",
        [_withSubmissionId(entry, submissionId), _org, _me, entry.refId],
      );
    } else {
      await sql.update(
        'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [_org, _me, entry.refId],
      );
    }
  }

  String _withSubmissionId(OutboxEntry entry, String submissionId) =>
      pendingFormJson(
        submissionId,
        idText(entry.payload['name']),
        idText(entry.payload['caption']),
        ((entry.payload['values'] as Map?) ?? {}).cast<String, dynamic>(),
        definitions[idText(entry.payload['name'])],
        _me ?? '',
      );

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
      "status, approval_json, rejection_json, edited_ts, sync_state) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,'synced')",
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
        s['rejection'] == null ? null : jsonEncode(s['rejection']),
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
          : _resetToPending(entry));
    }
    await syncFromServer();
    await flush();
  }

  Future<void> _resetToPending(OutboxEntry entry) async {
    await _setStatus(entry, 'pending');
    await _setMessageStatus(entry, 'pending');
  }

  // ---- sample data (SEED_UI) -----------------------------------------------------

  /// With the sample data on, a save walks through pending and sent on a
  /// timer, in memory. A text answer of "fail" is refused, to see that state.
  void _seedSubmit(
    String name,
    Map<String, dynamic> values, {
    required String caption,
    String? chat,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp-$now';
    final finalId = '${1100 + submissions.length}';
    final def = definitions[name];
    FormSubmission build(String id, String state) => FormSubmission(
      submissionId: id,
      tstruct: name,
      byUser: SeedMessages.me,
      ts: now,
      valuesJson: jsonEncode(values),
      syncState: state,
    );
    submissions.insert(0, build(tempId, 'pending_create'));
    final fails = values.values.any((v) => v == 'fail');
    String json(String id) =>
        pendingFormJson(id, name, caption, values, def, SeedMessages.me);
    if (chat != null) {
      SeedMessages.sendForm(
        chat,
        tempId,
        finalId,
        json(tempId),
        json(finalId),
        caption.isEmpty ? name : caption,
        fails: fails,
      );
    }
    Timer(const Duration(milliseconds: 1600), () {
      if (fails) return;
      submissions
        ..removeWhere((s) => s.submissionId == tempId)
        ..insert(0, build(finalId, 'synced'));
    });
  }

  void _seedEdit(String id, Map<String, dynamic> values) {
    final i = submissions.indexWhere((s) => s.submissionId == id);
    if (i < 0) return;
    final old = submissions[i];
    submissions[i] = FormSubmission(
      submissionId: old.submissionId,
      tstruct: old.tstruct,
      byUser: old.byUser,
      ts: old.ts,
      valuesJson: jsonEncode(values),
      syncState: 'synced',
      editedTs: DateTime.now().millisecondsSinceEpoch,
    );
    SeedMessages.updateForm(
      id,
      pendingFormJson(
        id,
        old.tstruct,
        definitions[old.tstruct]?.caption ?? '',
        values,
        definitions[old.tstruct],
        SeedMessages.me,
      ),
    );
  }

  /// True when the list was fetched; false when the server could not be
  /// reached or refused (the cached rows stay either way).
  Future<bool> syncFromServer() async {
    if (SeedUi.isActive) return true;
    if (_org == null || _me == null) return false;
    var offset = 0;
    var isOk = true;
    try {
      for (var page = 0; page < 5; page++) {
        final data = await _socket.sdCall('submissions.list', {
          'offset': offset,
        });
        final list = ((data['submissions'] as List?) ?? []).cast<Map>();
        final scopes = <String, String>{
          for (final s in list) idText(s['tstruct']): idText(s['scope']),
        };
        final structures = data['structures'];
        await _db.transaction((sql) async {
          for (final s in list) {
            await _upsertServer(sql, s.cast<String, dynamic>());
          }
          if (structures is Map) {
            for (final e in structures.entries) {
              if (e.value is Map) {
                await _storeCaptions(
                  sql,
                  idText(e.key),
                  scopes[idText(e.key)] ?? '',
                  e.value as Map,
                );
              }
            }
          }
        });
        if (data['hasMore'] != true || list.isEmpty) break;
        offset += list.length;
      }
    } on SocketCallError catch (_) {
      isOk = false;
    }
    await reload();
    return isOk;
  }

  /// The captions a list answer carries. A full definition that was fetched
  /// is never replaced by them.
  Future<void> _storeCaptions(Sql sql, String name, String scope, Map structure) async {
    final json = FormDefinition.captionsJson(structure);
    final args = [
      idText(structure['caption']),
      json,
      scope,
      DateTime.now().millisecondsSinceEpoch,
      _org,
      _me,
      name,
    ];
    final updated = await sql.update(
      'UPDATE form_definitions SET caption = ?, definition_json = ?, scope = ?, fetched_ts = ? '
      "WHERE org_id = ? AND user_id = ? AND name = ? AND definition_json LIKE '%\"${FormDefinition.captionsOnlyMarker}\":true%'",
      args,
    );
    if (updated == 0) {
      await sql.insert(
        'INSERT OR IGNORE INTO form_definitions(caption, definition_json, scope, fetched_ts, org_id, user_id, name) VALUES(?,?,?,?,?,?,?)',
        args,
      );
    }
  }

  bool hasFullDefinition(String name) => definitions[name]?.isFull ?? false;

  /// The full definition of a form, fetched when online and kept for offline.
  /// A form a person made (`user`) is read with `tstruct.user.get`, an
  /// admin's with `tstruct.get`; with no scope given both are tried, user
  /// first. Null when it can't be had.
  Future<FormDefinition?> definition(String name, {String scope = ''}) async {
    if (SeedUi.isActive) return definitions[name];
    final org = _org;
    final user = _me;
    if (org == null || user == null || name.isEmpty) return null;
    final known = scope.isNotEmpty ? scope : definitions[name]?.scope ?? '';
    if (_socket.isOnline) {
      final scopes = known == 'user'
          ? const ['user']
          : known.isEmpty
          ? const ['user', 'admin']
          : const ['admin'];
      for (final s in scopes) {
        try {
          final data = await _socket.sdCall(
            s == 'user' ? 'tstruct.user.get' : 'tstruct.get',
            {'name': name},
          );
          final tstruct = (data['tstruct'] as Map).cast<String, dynamic>();
          await _db.insert(
            'INSERT OR REPLACE INTO form_definitions(org_id, user_id, name, scope, caption, definition_json, fetched_ts) VALUES(?,?,?,?,?,?,?)',
            [
              org,
              user,
              name,
              s,
              idText(tstruct['caption']),
              jsonEncode(tstruct),
              DateTime.now().millisecondsSinceEpoch,
            ],
          );
          final parsed = FormDefinition.fromMap(name, s, tstruct);
          definitions[name] = parsed;
          return parsed;
        } on SocketCallError catch (_) {
          continue;
        } on TypeError catch (_) {
          continue;
        }
      }
    }
    return definitions[name];
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
