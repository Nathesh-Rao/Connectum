import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:get/get.dart';

import '../../core/debug/records_log.dart';
import '../../core/debug/seed_messages.dart';
import '../../core/debug/seed_tickets.dart';
import '../../core/debug/seed_ui.dart';
import '../db/app_database.dart';
import '../records/paged_read.dart';
import '../records/record_commands.dart';
import '../models/form_card.dart';
import '../models/form_entry.dart';
import '../models/form_definition.dart';
import '../models/form_submission.dart';
import '../models/ids.dart';
import '../models/message.dart';
import '../models/outbox_entry.dart';
import '../session_store.dart';
import 'form_options_repository.dart';
import 'message_repository.dart';
import '../socket/socket_service.dart';
import '../../core/log/safe.dart';
import '../../core/log/app_log.dart';

/// A submission the server accepted: [isPending] when it waits for approval.
class SavedRecord {
  const SavedRecord({
    required this.id,
    required this.tstruct,
    this.isPending = false,
    this.isDuplicate = false,
    this.isNotPosted = false,
  });

  final int id;
  final String tstruct;
  final bool isPending;

  /// The answer to a repeated `cid`: nothing was saved twice.
  final bool isDuplicate;

  /// A chat was given and the record was saved, but the server could not
  /// post the card (`message: null`).
  final bool isNotPosted;
}

class SubmissionRepository extends GetxService {
  SubmissionRepository(
    this._db,
    this._session,
    this._socket,
    this._messages,
    this._options,
  );

  static const couldNotConfirm = "couldn't confirm delivery";
  static const invalidReason = 'Some answers need fixing.';
  static const notPostedReason =
      "Couldn't post to this chat. Nothing was saved.";

  /// The server remembers a client id for one day; an entry first sent longer
  /// ago than this can no longer be sent safely again.
  static const _cidMemory = Duration(hours: 23);
  static const _kinds = "('form_submit','form_edit','form_resubmit')";

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final MessageRepository _messages;
  final FormOptionsRepository _options;

  /// A plain-words problem with a save that happened in the background (an
  /// edit that was refused); the open screen shows it once.
  final notice = RxnString();

  final submissions = <FormSubmission>[].obs;

  final _saved = StreamController<SavedRecord>.broadcast();

  /// A new submission the server accepted (`tstruct.submit` answered, or
  /// answered again for the same `cid` with `duplicate: true`): saved, or
  /// waiting for approval. Auto-send rules have already run by now.
  Stream<SavedRecord> get saved => _saved.stream;

  /// The forms the cached submissions belong to, by form name: full ones where
  /// a definition was fetched, captions only otherwise.
  final definitions = <String, FormDefinition>{}.obs;
  final isLoaded = false.obs;

  /// Saves that never reached the server and won't on their own: the local id
  /// of each and the plain reason. A card shows them as failed.
  final failures = <String, String>{}.obs;

  /// Saves kept on the phone as drafts: the local id of each and the captions
  /// of the made-for fields still empty. A draft is never sent on its own.
  final drafts = <String, List<String>>{}.obs;
  bool _isFlushing = false;

  String? get _org => _session.orgId;
  String? get _me => _session.userId;

  @override
  void onInit() {
    super.onInit();
    _socket.listenOnline('submissions', _onOnline);
    ever(_session.current, (_) {
      // The other organisation's forms go before the new one's first read.
      submissions.clear();
      definitions.clear();
      failures.clear();
      drafts.clear();
      isLoaded.value = false;
      reload();
    });
    reload();
  }

  Future<void> reload() async {
    if (SeedUi.isActive) {
      definitions.assignAll(SeedUi.definitions());
      submissions.assignAll(SeedUi.submissions());
      failures.assignAll(SeedUi.formFailures);
      drafts.assignAll(SeedUi.formDrafts);
      isLoaded.value = true;
      return;
    }
    if (_org == null || _me == null) {
      submissions.clear();
      definitions.clear();
      return;
    }
    final defs = await _db.query(
      'SELECT name, scope, definition_json, rev, fetched_ts FROM form_definitions WHERE org_id = ? AND user_id = ?',
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
          rev: idText(d['rev']),
          fetchedTs: intOf(d['fetched_ts']),
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
    final kept = await _db.query(
      "SELECT ref_id, payload_json FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'draft' AND kind = 'form_submit'",
      [_org, _me],
    );
    drafts.assignAll({
      for (final d in kept)
        idText(d['ref_id']): OutboxEntry.waitingOf(idText(d['payload_json'])),
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
      return FormCardData.fromSubmission(
        mine,
        definition: definitions[mine.tstruct],
      );
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
    List<String>? waiting,
  }) async {
    if (SeedUi.isActive) {
      if (waiting != null) {
        _seedDraft(name, values, waiting, caption: caption, scope: scope);
      } else {
        _seedSubmit(name, values, caption: caption, chat: chat);
      }
      return;
    }
    final isDraft = waiting != null;
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
        "VALUES(?,?,?,'form_submit',?,?,?,?,?)",
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
            if (isDraft) 'waiting': waiting,
          }),
          tempId,
          isDraft ? 'draft' : 'pending',
          now,
          cid,
        ],
      );
      if (chat != null && !isDraft) {
        await _putPendingMessage(
          sql,
          tempId,
          chat,
          name,
          caption,
          values,
          now,
          cid: cid,
        );
      }
    });
    await reload();
    if (chat != null && !isDraft) await _messages.reloadAfterLocalChange();
    if (!isDraft) fireAndLog('submission_repository', () => flush());
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
          if (!def.isGridSection(f.section) && values.containsKey(f.name))
            f.name,
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

  /// The `sd` action of a new submission, by the form's scope.
  static String submitCommand(String scope) =>
      scope == 'user' ? RecordCmd.userSubmit : RecordCmd.submit;

  /// The request of a new submission: the name, the values and the one `cid`
  /// of the save; `chat` only when the form is posted into a chat. Never a
  /// `ref` or `meta`.
  static Map<String, dynamic> submitArgs(
    Map<String, dynamic> payload,
    String cid,
  ) => {
    'name': idText(payload['name']),
    'values': payload['values'],
    if (payload['chat'] != null) 'chat': payload['chat'],
    'cid': cid,
  };

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
    // `submissions.update` replaces every value and has no version check: a
    // newer edit by someone else is overwritten. The web says nothing either.
    RecordsLog.line('edit $id sends the full value set; no version check');
    await _queueSaved('form_edit', id, values, cid);
  }

  /// Deletes a submission of mine (`submissions.delete {id}`). Needs a
  /// connection and is never queued. Null when it is gone; otherwise the
  /// words to show (never the raw server code). The list, and with it My
  /// Work Space, is read again afterwards; the history rows of the record
  /// stay on the server.
  Future<String?> deleteSubmission(String id) async {
    final number = int.tryParse(id);
    if (number == null) return "That submission isn't sent yet.";
    if (SeedUi.isActive) {
      submissions.removeWhere((s) => s.submissionId == id);
      return null;
    }
    final org = _org;
    final user = _me;
    if (org == null || user == null) return deleteFailed;
    if (!_socket.isOnline) return 'Needs a connection';
    try {
      await _socket.sdCall(RecordCmd.delete, {'id': number});
    } on SocketCallError catch (e) {
      if (e.code == 'not_found') {
        await _forget(id);
        return 'That submission no longer exists.';
      }
      fireAndLog('submission_repository', () => syncFromServer());
      return switch (e.code) {
        'submission_locked' =>
          "It can't be deleted while it waits for approval or after it was approved.",
        'forbidden' => 'Only the person who submitted it can delete it.',
        'rate_limited' => 'Too many requests. Try again in a moment.',
        _ => e.isConnectionGap ? 'Needs a connection' : deleteFailed,
      };
    }
    await _forget(id);
    fireAndLog('submission_repository', () => syncFromServer());
    return null;
  }

  static const deleteFailed = "Couldn't delete it. Try again.";

  Future<void> _forget(String id) async {
    await _db.update(
      'DELETE FROM form_submissions WHERE org_id = ? AND user_id = ? AND submission_id = ?',
      [_org, _me, id],
    );
    await reload();
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
    fireAndLog('submission_repository', () => flush());
  }

  /// Fixes a submission that never reached the server (it was refused, or
  /// still waits, or is a draft): the entry keeps its place, its id and its
  /// client id and is sent again. With [waiting] it stays a draft instead.
  Future<void> resendFailed(
    String refId,
    Map<String, dynamic> values, {
    List<String>? waiting,
  }) async {
    if (SeedUi.isActive) {
      _seedResend(refId, values, waiting);
      return;
    }
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final rows = await _db.query(
      "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND ref_id = ? AND kind = 'form_submit' AND status IN ('pending','failed','draft')",
      [org, user, refId],
    );
    if (rows.isEmpty) return;
    final entry = OutboxEntry.fromRow(rows.first);
    final wasDraft = entry.status == 'draft';
    final isDraft = waiting != null;
    final payload = {...entry.payload, 'values': values}
      ..remove('errors')
      ..remove('waiting');
    if (isDraft) payload['waiting'] = waiting;
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET payload_json = ?, status = ?, retry_count = 0, next_attempt_ts = 0, "
        'last_error = NULL, first_attempt_ts = NULL WHERE id = ?',
        [jsonEncode(payload), isDraft ? 'draft' : 'pending', entry.id],
      );
      await sql.update(
        'UPDATE form_submissions SET values_json = ? WHERE org_id = ? AND user_id = ? AND submission_id = ?',
        [jsonEncode(values), org, user, refId],
      );
      final chat = payload['chat'];
      if (chat is String && !isDraft) {
        await _putPendingMessage(
          sql,
          refId,
          chat,
          idText(payload['name']),
          idText(payload['caption']),
          values,
          wasDraft ? DateTime.now().millisecondsSinceEpoch : entry.createdTs,
          cid: entry.cid ?? '',
          isReplace: !wasDraft,
        );
      }
    });
    await reload();
    await _messages.reloadAfterLocalChange();
    if (!isDraft) fireAndLog('submission_repository', () => flush());
  }

  /// What a failed or waiting submission was filled in with, and the server's
  /// complaint about it, for "Edit and resend".
  Future<
    ({
      Map<String, dynamic> values,
      Object? errors,
      String name,
      String scope,
      String caption,
      bool isDraft,
    })?
  >
  pendingFor(String refId) async {
    if (SeedUi.isActive) return SeedUi.formPending[refId];
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
      isDraft: OutboxEntry.fromRow(rows.first).status == 'draft',
    );
  }

  /// Sends a refused post-to-chat save again with no `chat` and a new `cid`
  /// (the old one belongs to the refused attempt); the card leaves the chat.
  Future<void> saveWithoutPosting(String refId) async {
    final rows = await _db.query(
      "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND ref_id = ? AND kind = 'form_submit' AND status = 'failed'",
      [_org, _me, refId],
    );
    if (rows.isEmpty) return;
    final entry = OutboxEntry.fromRow(rows.first);
    final payload = {...entry.payload, 'chat': null};
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET payload_json = ?, conv_id = '', cid = ?, status = 'pending', retry_count = 0, "
        'next_attempt_ts = 0, last_error = NULL, first_attempt_ts = NULL WHERE id = ?',
        [jsonEncode(payload), newCid(), entry.id],
      );
      await sql.update(
        'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [_org, _me, refId],
      );
    });
    await _messages.reloadAfterLocalChange();
    fireAndLog('submission_repository', () => flush());
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
    fireAndLog('submission_repository', () => flush());
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
          submitCommand(scope),
          submitArgs(entry.payload, cid),
        );
        final submission = (data['submission'] as Map).cast<String, dynamic>();
        await _adopt(
          entry,
          submission,
          data['recordStatus'],
          message: data['message'] is Map
              ? (data['message'] as Map).cast<String, dynamic>()
              : null,
        );
        final id = idNumber(submission['id']);
        if (id != null && !_saved.isClosed) {
          _saved.add(
            SavedRecord(
              id: id,
              tstruct: name,
              isPending: data['recordStatus'] == 'pending',
              isDuplicate: data['duplicate'] == true,
              isNotPosted:
                  idText(entry.payload['chat']).isNotEmpty &&
                  data.containsKey('message') &&
                  data['message'] == null &&
                  data['recordStatus'] != 'pending',
            ),
          );
        }
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
    if (entry.kind == 'form_submit' &&
        idText(entry.payload['chat']).isNotEmpty &&
        (e.code == 'not_found' || e.code == 'invalid')) {
      // A bad chat target is checked before saving: nothing was saved.
      await _fail(entry, notPostedReason);
      return;
    }
    if (e.code == 'invalid_values') await _dropRefusedLists(entry, e.details);
    if (e.code == 'invalid_values' && entry.kind == 'form_submit') {
      await _db.update('UPDATE outbox SET payload_json = ? WHERE id = ?', [
        jsonEncode({...entry.payload, 'errors': e.details}),
        entry.id,
      ]);
    }
    await _fail(entry, _plainReason(e));
  }

  /// A choice the server refused: the lists kept for that field are dropped,
  /// so the next time the form opens it asks again.
  Future<void> _dropRefusedLists(OutboxEntry entry, Object? details) async {
    final fields = details is Map ? details['fields'] : null;
    if (fields is! Map) return;
    final name = idText(entry.payload['name']);
    final def = definitions[name];
    if (def == null || _org == null || _me == null) return;
    for (final key in fields.keys) {
      final field = def.fieldOf(idText(key).split('.').last);
      if (field == null || field.type != 'selection') continue;
      await _options.dropField(name, field.name);
    }
  }

  static String _plainReason(SocketCallError e) {
    if (e.code == 'invalid_values') return invalidReason;
    if (e.code == 'submission_locked') {
      return "It can't be changed while it waits for approval.";
    }
    if (e.code == 'not_found') return 'That submission no longer exists.';
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
    if (e.kind == 'form_submit') fireAndLog('submission_repository', () => reload());
    if (e.kind != 'form_submit') {
      // A refused edit leaves the server's version in place.
      await _db.update(
        "UPDATE form_submissions SET sync_state = 'synced' WHERE org_id = ? AND user_id = ? AND submission_id = ? AND sync_state = 'pending_edit'",
        [_org, _me, e.refId],
      );
      notice.value = reason == couldNotConfirm
          ? "An edit couldn't be confirmed. Check the submission."
          : 'An edit was not saved: $reason';
      fireAndLog('submission_repository', () => syncFromServer());
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
        // The echo arrived first: it takes over the cid so the card keeps its key.
        await sql.update(
          'UPDATE messages SET cid = COALESCE(cid, ?) WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [entry.cid, _org, _me, serverId],
        );
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
    final isRecord = SeedTickets.isActive && SeedTickets.handles(name);
    final finalId = isRecord
        ? '${SeedTickets.addFromForm(name, values)}'
        : '${1100 + submissions.length}';
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
      final number = int.tryParse(finalId);
      if (isRecord && number != null && !_saved.isClosed) {
        _saved.add(SavedRecord(id: number, tstruct: name));
      }
    });
  }

  void _seedDraft(
    String name,
    Map<String, dynamic> values,
    List<String> waiting, {
    required String caption,
    required String scope,
  }) {
    final id = 'temp-${DateTime.now().millisecondsSinceEpoch}';
    SeedUi.formDrafts[id] = waiting;
    SeedUi.formPending[id] = (
      values: values,
      errors: null,
      name: name,
      scope: scope,
      caption: caption,
      isDraft: true,
    );
    submissions.insert(
      0,
      FormSubmission(
        submissionId: id,
        tstruct: name,
        byUser: SeedMessages.me,
        ts: DateTime.now().millisecondsSinceEpoch,
        valuesJson: jsonEncode(values),
        syncState: 'pending_create',
      ),
    );
    drafts.assignAll(SeedUi.formDrafts);
  }

  /// A draft saved again, or a draft / refused record sent.
  void _seedResend(
    String refId,
    Map<String, dynamic> values,
    List<String>? waiting,
  ) {
    final held = SeedUi.formPending[refId];
    if (held == null) return;
    if (waiting != null) {
      SeedUi.formDrafts[refId] = waiting;
      SeedUi.formPending[refId] = (
        values: values,
        errors: null,
        name: held.name,
        scope: held.scope,
        caption: held.caption,
        isDraft: true,
      );
      drafts.assignAll(SeedUi.formDrafts);
      return;
    }
    SeedUi.formDrafts.remove(refId);
    SeedUi.formFailures.remove(refId);
    SeedUi.formPending.remove(refId);
    submissions.removeWhere((s) => s.submissionId == refId);
    failures.assignAll(SeedUi.formFailures);
    drafts.assignAll(SeedUi.formDrafts);
    _seedSubmit(held.name, values, caption: held.caption);
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

  /// `submissions.list` pages read per sync (100 rows each; the web reads 10
  /// too). Older records are not cached; reaching the limit is logged.
  static const ownPages = 10;

  /// The pause between two pages (30 commands per 10 s are allowed).
  Duration pageGap = const Duration(milliseconds: 350);

  Future<bool>? _syncing;

  /// True when the list was fetched; false when the server could not be
  /// reached or refused (the cached rows stay either way, and the failure is
  /// logged). One read at a time: a call during a read gets its result.
  Future<bool> syncFromServer() {
    if (SeedUi.isActive) return Future.value(true);
    return _syncing ??= _sync().whenComplete(() => _syncing = null);
  }

  Future<bool> _sync() async {
    final org = _org;
    final me = _me;
    if (org == null || me == null) return false;
    final result = await PagedRead.run(
      label: 'submissions.list org=$org',
      maxPages: ownPages,
      gap: pageGap,
      isStale: () => _org != org || _me != me,
      page: (offset) async {
        final args = <String, dynamic>{'offset': offset};
        final Map<String, dynamic> data;
        try {
          data = await _socket.sdCall('submissions.list', args);
          RecordsLog.call(
            'submissions.list',
            args,
            org: org,
            user: me,
            reply: data,
          );
        } on SocketCallError catch (e) {
          RecordsLog.call(
            'submissions.list',
            args,
            org: org,
            user: me,
            error: e.code,
          );
          rethrow;
        }
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
        return (received: list.length, hasMore: data['hasMore'] == true);
      },
    );
    if (result.error != 'stale') await reload();
    return result.isOk;
  }

  /// The captions a list answer carries. A full definition that was fetched
  /// is never replaced by them.
  Future<void> _storeCaptions(
    Sql sql,
    String name,
    String scope,
    Map structure,
  ) async {
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
  Future<FormDefinition?> definition(
    String name, {
    String scope = '',
    Duration? maxAge,
  }) async {
    if (SeedUi.isActive) return definitions[name];
    final kept = definitions[name];
    if (maxAge != null &&
        kept != null &&
        kept.isFull &&
        (scope.isEmpty || kept.scope == scope) &&
        DateTime.now().millisecondsSinceEpoch - kept.fetchedTs <
            maxAge.inMilliseconds) {
      return kept;
    }
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
          final parsed = await _keepDefinition(
            name,
            s,
            tstruct,
            idText(data['rev']),
          );
          return parsed;
        } on SocketCallError catch (e) {
          AppLog.w('submission_repository', 'socket ${e.code}');
          continue;
        } on TypeError catch (e, st) {
          AppLog.e('submission_repository', e, st, 'structure parse');
          continue;
        }
      }
    }
    return definitions[name];
  }

  /// Stores a form's full definition for this organisation and person.
  Future<FormDefinition> _keepDefinition(
    String name,
    String scope,
    Map<String, dynamic> tstruct,
    String rev,
  ) async {
    final org = _org!;
    final user = _me!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = await _db.query(
      'SELECT rev FROM form_definitions WHERE org_id = ? AND user_id = ? AND name = ?',
      [org, user, name],
    );
    // Another version of the form: what was kept for the old one goes.
    if (before.isNotEmpty && idText(before.first['rev']) != rev) {
      await _options.dropForm(name);
    }
    await _db.insert(
      'INSERT OR REPLACE INTO form_definitions(org_id, user_id, name, scope, caption, definition_json, fetched_ts, rev) VALUES(?,?,?,?,?,?,?,?)',
      [
        org,
        user,
        name,
        scope,
        idText(tstruct['caption']),
        jsonEncode(tstruct),
        now,
        rev,
      ],
    );
    final parsed = FormDefinition.fromMap(
      name,
      scope,
      tstruct,
      rev: rev,
      fetchedTs: now,
    );
    definitions[name] = parsed;
    return parsed;
  }

  /// What `#tstruct-add <name>` does first, as the web does: `tstruct.user.open`
  /// with `mode: add` (the server takes the caption or the name and checks the
  /// person may fill it), once per opening. The definition it returns is kept,
  /// so the form screen does not ask again. Offline, a form already kept on
  /// the device (by name or caption) opens from the cache.
  Future<StructureOpen> openStructure(String typed) async {
    final text = typed.trim();
    if (text.isEmpty) return const StructureOpen.failed('', isUsage: true);
    if (SeedUi.isActive) {
      final lower = text.toLowerCase();
      final hit = definitions.values
          .where(
            (d) =>
                d.isFull &&
                (d.name.toLowerCase() == lower ||
                    d.caption.toLowerCase() == lower),
          )
          .firstOrNull;
      return hit == null
          ? const StructureOpen.failed(
              'No such structure, or it is not available to you.',
              code: 'not_found',
            )
          : StructureOpen(hit.name, hit.scope, hit.caption);
    }
    if (_org == null || _me == null) return const StructureOpen.failed('');
    if (!_socket.isOnline) {
      final lower = text.toLowerCase();
      final kept = definitions.values
          .where(
            (d) =>
                d.isFull &&
                (d.name.toLowerCase() == lower ||
                    d.caption.toLowerCase() == lower),
          )
          .firstOrNull;
      return kept == null
          ? const StructureOpen.failed('', isOffline: true)
          : StructureOpen(kept.name, kept.scope, kept.caption);
    }
    try {
      final data = await _socket.sdCall(RecordCmd.openStructure, {
        'name': text,
        'mode': 'add',
      });
      final tstruct = (data['tstruct'] as Map).cast<String, dynamic>();
      final name = idText(tstruct['name']);
      final scope = idText(data['scope']) == 'admin' ? 'admin' : 'user';
      if (name.isEmpty) return const StructureOpen.failed('');
      final def = await _keepDefinition(
        name,
        scope,
        tstruct,
        idText(data['rev']),
      );
      return StructureOpen(name, scope, def.caption);
    } on SocketCallError catch (e) {
      return StructureOpen.failed(
        e.message,
        isOffline: e.isConnectionGap,
        code: e.code,
      );
    } on TypeError catch (e, st) {
      AppLog.e('submission_repository', e, st, 'structure parse');
      return const StructureOpen.failed('');
    }
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

/// The answer of `SubmissionRepository.openStructure`: the form to open, or
/// why there is none.
class StructureOpen {
  const StructureOpen(this.name, this.scope, this.caption)
    : message = '',
      code = '',
      isOffline = false,
      isUsage = false;

  const StructureOpen.failed(
    this.message, {
    this.code = '',
    this.isOffline = false,
    this.isUsage = false,
  }) : name = '',
       scope = '',
       caption = '';

  final String name;
  final String scope;
  final String caption;
  final String message;
  final String code;
  final bool isOffline;
  final bool isUsage;

  bool get isOpen => name.isNotEmpty;
}
