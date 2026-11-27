import 'dart:async';

import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../core/log/safe.dart';
import '../db/app_database.dart';
import '../marks/mark_commands.dart';
import '../models/ids.dart';
import '../models/message_mark.dart';
import '../models/self_conversation.dart';
import '../session_store.dart';
import '../socket/read_gate.dart';
import '../socket/socket_service.dart';

enum _Field { saved, pinned }

enum _Out { done, dropped, stopped }

/// Saved and pinned messages (`msg.*`). Today it serves the person's own
/// notes in My Work Space only (`conv` is always `self`); every query and
/// command takes the conversation from [_conv], so direct chats and groups
/// only need their `conv` name (`dm:<user>`, `group:<name>`) and their own
/// screens.
///
/// SQLite is the source: a change is written at once as a wish
/// (`want_saved` / `want_pinned`) that shows on screen, then sent one command
/// at a time (paced by the socket like any chat command). The server's answer
/// makes it the confirmed state; a refusal puts the old state back with a
/// short notice; a connection gap keeps the wish and sends it again when the
/// phone is online. Repeating a save or a pin is safe on the server.
/// `msg.pins` and `msg.saved` (reads) go through the shared [ReadGate]; the
/// event `pins_changed` re-reads the pins once for a burst.
class MarksRepository extends GetxService {
  MarksRepository(
    this._db,
    this._session,
    this._socket,
    this._gate, {
    this.readDelay = const Duration(milliseconds: 600),
    this.retryDelay = const Duration(seconds: 15),
    this.timer = Timer.new,
  });

  static const _tag = 'marks';
  static const _conv = SelfConversation.id;

  /// The server's limit of pins per conversation until `msg.pins` says.
  static const defaultPinMax = 10;

  static const couldNot = "That didn't work. Try again";
  static const noteGone = 'That note is gone';

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final ReadGate _gate;

  /// How long a read waits so a burst of events becomes one read.
  final Duration readDelay;

  /// How long a wish waits before it is sent again after a gap.
  final Duration retryDelay;

  /// Replaceable so a test can fire the timers by hand.
  final Timer Function(Duration, void Function()) timer;

  /// The marks of my notes by note id (a note with none has no entry).
  final marks = <String, MessageMark>{}.obs;

  /// The pinned notes, newest pin first (also the ones still waiting).
  final pinned = <MessageMark>[].obs;
  final pinMax = defaultPinMax.obs;

  final _notices = StreamController<String>.broadcast();

  /// Short plain-words lines about a change that was refused.
  Stream<String> get notices => _notices.stream;

  /// Reads sent (tests).
  int pinReads = 0;
  int savedReads = 0;

  bool _isFlushing = false;
  bool _wantsFlush = false;
  Timer? _retry;
  Timer? _pinsTimer;
  Timer? _savedTimer;
  bool _isReadingPins = false;
  bool _isReadingSaved = false;
  bool _pinsAgain = false;
  bool _savedAgain = false;

  String? get _org => _session.orgId;
  String? get _me => _session.userId;
  bool get _canWork => _session.hasSession && _org != null && _me != null;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(
      (e) => fireAndLog(_tag, () => onEvent(e)),
      onError: streamOnError(_tag),
    );
    _socket.listenOnline(_tag, _onOnline);
    ever(_session.current, (_) {
      marks.clear();
      pinned.clear();
      fireAndLog(_tag, open);
    });
  }

  @override
  void onClose() {
    _retry?.cancel();
    _pinsTimer?.cancel();
    _savedTimer?.cancel();
    _notices.close();
    super.onClose();
  }

  Future<void> _onOnline() async {
    if (!_canWork) return;
    await flush();
    requestPins();
    requestSaved();
  }

  /// Reads the stored marks (no network needed), sends what waits and asks
  /// the server for the lists when online.
  Future<void> open() async {
    await load();
    if (!_canWork || !_socket.isOnline) return;
    fireAndLog(_tag, flush);
    requestPins();
    requestSaved();
  }

  bool isSaved(String msgId) => marks[msgId]?.isSaved ?? false;
  bool isPinned(String msgId) => marks[msgId]?.isPinned ?? false;

  /// Reads the marks of the notes that are not deleted into [marks] and
  /// [pinned].
  Future<void> load() async {
    final org = _org;
    final me = _me;
    if (org == null || me == null) {
      marks.clear();
      pinned.clear();
      return;
    }
    final rows = await _db.query(
      'SELECT k.* FROM message_marks k LEFT JOIN messages m ON m.org_id = k.org_id '
      'AND m.user_id = k.user_id AND m.msg_id = k.msg_id '
      'WHERE k.org_id = ? AND k.user_id = ? AND k.conv_id = ? AND COALESCE(m.is_deleted, 0) = 0',
      [org, me, _conv],
    );
    if (org != _org || me != _me) return;
    final all = [for (final r in rows) MessageMark.fromRow(r)];
    marks.assignAll({for (final m in all) m.msgId: m});
    final pins = all.where((m) => m.isPinned).toList()
      ..sort((a, b) {
        final byTime = b.pinnedTs.compareTo(a.pinnedTs);
        return byTime != 0
            ? byTime
            : (numericId(b.msgId) ?? 0).compareTo(numericId(a.msgId) ?? 0);
      });
    pinned.assignAll(pins);
  }

  // ---- changes -------------------------------------------------------------

  Future<void> toggleSave(String msgId) => _change(msgId, _Field.saved, null);

  Future<void> togglePin(String msgId) => _change(msgId, _Field.pinned, null);

  Future<void> unpin(String msgId) => _change(msgId, _Field.pinned, false);

  /// Writes the wish ([to]: null toggles what shows now) and sends it. A
  /// note with no server id cannot be marked (it is not in the server's
  /// store yet).
  Future<void> _change(String msgId, _Field field, bool? to) async {
    final org = _org;
    final me = _me;
    if (org == null || me == null) return;
    if (numericId(msgId) == null) {
      AppLog.w(_tag, 'ignored change of a note with no server id');
      return;
    }
    final args = [org, me, _conv, msgId];
    String? did;
    await _db.transaction((sql) async {
      final rows = await sql.query(
        'SELECT * FROM message_marks WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
        args,
      );
      if (rows.isEmpty) {
        await sql.insert(
          'INSERT INTO message_marks(org_id, user_id, conv_id, msg_id) VALUES(?,?,?,?)',
          args,
        );
      }
      final now = rows.isEmpty ? null : MessageMark.fromRow(rows.first);
      final shows = field == _Field.saved
          ? (now?.isSaved ?? false)
          : (now?.isPinned ?? false);
      final target = to ?? !shows;
      final confirmed = field == _Field.saved
          ? (now?.isConfirmedSaved ?? false)
          : (now?.isConfirmedPinned ?? false);
      final want = target == confirmed ? null : (target ? 1 : 0);
      if (field == _Field.saved) {
        await sql.update(
          'UPDATE message_marks SET want_saved = ?, saved_ts = ? WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
          [want, DateTime.now().millisecondsSinceEpoch, ...args],
        );
        did = target ? 'save' : 'unsave';
      } else {
        await sql.update(
          'UPDATE message_marks SET want_pinned = ?, pinned_ts = CASE WHEN ? = 1 THEN ? ELSE pinned_ts END, '
          'pinned_by = CASE WHEN ? = 1 THEN ? ELSE pinned_by END '
          'WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
          [
            want,
            target && !confirmed ? 1 : 0,
            DateTime.now().millisecondsSinceEpoch,
            target && !confirmed ? 1 : 0,
            me,
            ...args,
          ],
        );
        did = target ? 'pin' : 'unpin';
      }
      await _dropEmpty(sql, org, me);
    });
    AppLog.i(_tag, 'queued $did id=$msgId');
    await load();
    fireAndLog(_tag, flush);
  }

  Future<void> _dropEmpty(Sql sql, String org, String me) => sql.update(
    'DELETE FROM message_marks WHERE org_id = ? AND user_id = ? AND is_saved = 0 AND is_pinned = 0 '
    'AND want_saved IS NULL AND want_pinned IS NULL',
    [org, me],
  );

  // ---- sending -------------------------------------------------------------

  /// Sends the wishes one at a time, oldest first. Stops at a gap or a rate
  /// limit and tries again later; a refusal ends that one wish.
  Future<void> flush() async {
    if (_isFlushing) {
      _wantsFlush = true;
      return;
    }
    _isFlushing = true;
    try {
      do {
        _wantsFlush = false;
        await _pass();
      } while (_wantsFlush);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _pass() async {
    var didPin = false;
    while (_socket.isOnline && _canWork) {
      final row = await _nextWanted();
      if (row == null) break;
      final field = row.wantSaved != null ? _Field.saved : _Field.pinned;
      final out = await _sendOne(row, field);
      if (out == _Out.done && field == _Field.pinned) didPin = true;
      if (out == _Out.stopped) {
        _scheduleRetry();
        break;
      }
    }
    // The pin list is read again after my own change, as the web does.
    if (didPin) requestPins();
  }

  Future<MessageMark?> _nextWanted() async {
    final rows = await _db.query(
      'SELECT k.* FROM message_marks k LEFT JOIN messages m ON m.org_id = k.org_id '
      'AND m.user_id = k.user_id AND m.msg_id = k.msg_id '
      'WHERE k.org_id = ? AND k.user_id = ? AND k.conv_id = ? '
      '  AND (k.want_saved IS NOT NULL OR k.want_pinned IS NOT NULL) AND COALESCE(m.is_deleted, 0) = 0 '
      'ORDER BY k.rowid LIMIT 1',
      [_org, _me, _conv],
    );
    return rows.isEmpty ? null : MessageMark.fromRow(rows.first);
  }

  void _scheduleRetry([Duration? after]) {
    _retry?.cancel();
    _retry = timer(after ?? retryDelay, () => fireAndLog(_tag, flush));
  }

  Future<_Out> _sendOne(MessageMark row, _Field field) async {
    final id = numericId(row.msgId);
    final org = _org;
    final me = _me;
    if (id == null || org == null || me == null) return _Out.dropped;
    final want = field == _Field.saved ? row.wantSaved! : row.wantPinned!;
    final action = field == _Field.saved
        ? (want ? MarkCmd.save : MarkCmd.unsave)
        : (want ? MarkCmd.pin : MarkCmd.unpin);
    final args = switch (action) {
      MarkCmd.save => MarkCmd.saveArgs(_conv, id),
      MarkCmd.unsave => MarkCmd.unsaveArgs(id),
      MarkCmd.pin || _ => MarkCmd.pinArgs(_conv, id),
    };
    try {
      await _socket.sdCall(action, args);
    } on SocketCallError catch (e) {
      return _refused(row, field, action, e);
    }
    if (org != _org || me != _me) return _Out.stopped;
    final scope = [org, me, _conv, row.msgId];
    await _db.transaction((sql) async {
      if (field == _Field.saved) {
        await sql.update(
          'UPDATE message_marks SET is_saved = ?, want_saved = NULL WHERE org_id = ? AND user_id = ? AND conv_id = ? '
          'AND msg_id = ? AND want_saved = ?',
          [want ? 1 : 0, ...scope, want ? 1 : 0],
        );
      } else {
        await sql.update(
          'UPDATE message_marks SET is_pinned = ?, want_pinned = NULL, '
          'pinned_by = CASE WHEN ? = 1 THEN ? ELSE NULL END WHERE org_id = ? AND user_id = ? AND conv_id = ? '
          'AND msg_id = ? AND want_pinned = ?',
          [want ? 1 : 0, want ? 1 : 0, me, ...scope, want ? 1 : 0],
        );
      }
      await _dropEmpty(sql, org, me);
    });
    AppLog.i(_tag, '$action ok id=${row.msgId}');
    await load();
    return _Out.done;
  }

  Future<_Out> _refused(
    MessageMark row,
    _Field field,
    String action,
    SocketCallError e,
  ) async {
    AppLog.w(_tag, '$action failed code=${e.code} id=${row.msgId}');
    if (e.isConnectionGap) return _Out.stopped;
    if (e.code == 'rate_limited' || e.code == 'busy') return _Out.stopped;
    final org = _org;
    final me = _me;
    if (org == null || me == null) return _Out.dropped;
    final scope = [org, me, _conv, row.msgId];
    if (e.code == 'not_found') {
      await _db.update(
        'DELETE FROM message_marks WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
        scope,
      );
      _notify(noteGone);
    } else {
      await _db.transaction((sql) async {
        await sql.update(
          field == _Field.saved
              ? 'UPDATE message_marks SET want_saved = NULL WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?'
              : 'UPDATE message_marks SET want_pinned = NULL WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
          scope,
        );
        await _dropEmpty(sql, org, me);
      });
      _notify(_noticeFor(field, e.code));
    }
    await load();
    return _Out.dropped;
  }

  String _noticeFor(_Field field, String code) {
    if (code != 'limit') return couldNot;
    return field == _Field.pinned
        ? 'You can pin at most ${pinMax.value} notes. Unpin one first'
        : 'Your saved list is full. Remove some first';
  }

  void _notify(String text) {
    if (!_notices.isClosed) _notices.add(text);
  }

  // ---- reading -------------------------------------------------------------

  /// Asks for the pin list once for a burst of asks.
  void requestPins() {
    if (_isReadingPins) {
      _pinsAgain = true;
      return;
    }
    if (_pinsTimer != null) return;
    _pinsTimer = timer(readDelay, () {
      _pinsTimer = null;
      fireAndLog(_tag, _readPins);
    });
  }

  Future<void> _readPins() async {
    _isReadingPins = true;
    try {
      await refreshPins();
    } finally {
      _isReadingPins = false;
      if (_pinsAgain) {
        _pinsAgain = false;
        requestPins();
      }
    }
  }

  void requestSaved() {
    if (_isReadingSaved) {
      _savedAgain = true;
      return;
    }
    if (_savedTimer != null) return;
    _savedTimer = timer(readDelay, () {
      _savedTimer = null;
      fireAndLog(_tag, _readSaved);
    });
  }

  Future<void> _readSaved() async {
    _isReadingSaved = true;
    try {
      await refreshSaved();
    } finally {
      _isReadingSaved = false;
      if (_savedAgain) {
        _savedAgain = false;
        requestSaved();
      }
    }
  }

  /// One `msg.pins` read now (through the gate); the server's list replaces
  /// what was confirmed, wishes that wait stay.
  Future<void> refreshPins() async {
    if (!_canWork || !_socket.isOnline) return;
    final org = _org;
    final me = _me;
    final Map<String, dynamic> data;
    try {
      pinReads++;
      data = await _gate.run(
        () => _socket.sdCall(MarkCmd.pins, MarkCmd.pinsArgs(_conv)),
      );
    } on SocketCallError catch (e) {
      AppLog.w(_tag, '${MarkCmd.pins} failed code=${e.code}');
      return;
    }
    if (org != _org || me != _me) return;
    await _applyPins(org!, me!, data);
  }

  Future<void> refreshSaved() async {
    if (!_canWork || !_socket.isOnline) return;
    final org = _org;
    final me = _me;
    final Map<String, dynamic> data;
    try {
      savedReads++;
      data = await _gate.run(
        () => _socket.sdCall(MarkCmd.saved, MarkCmd.savedIdsArgs),
      );
    } on SocketCallError catch (e) {
      AppLog.w(_tag, '${MarkCmd.saved} failed code=${e.code}');
      return;
    }
    if (org != _org || me != _me) return;
    await _applySaved(org!, me!, data);
  }

  Future<Set<String>> _deletedAmong(Sql sql, String org, String me) async {
    final rows = await sql.query(
      'SELECT msg_id FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? AND is_deleted = 1',
      [org, me, _conv],
    );
    return {for (final r in rows) idText(r['msg_id'])};
  }

  Future<void> _applyPins(
    String org,
    String me,
    Map<String, dynamic> data,
  ) async {
    final list = data['pins'];
    if (list is! List) return;
    final max = numericId(data['max']);
    if (max != null && max > 0) pinMax.value = max;
    final scope = [org, me, _conv];
    await _db.transaction((sql) async {
      final deleted = await _deletedAmong(sql, org, me);
      await sql.update(
        'UPDATE message_marks SET is_pinned = 0, pinned_by = NULL WHERE org_id = ? AND user_id = ? AND conv_id = ? AND is_pinned = 1',
        scope,
      );
      for (final item in list) {
        if (item is! Map) continue;
        final id = numericId(item['id']);
        if (id == null || deleted.contains('$id')) continue;
        final message = item['message'];
        final words = message is Map ? idText(message['text']) : '';
        final by = idText(item['by']);
        final ts = intOf(item['ts']);
        final preview = words.startsWith('e2e1:') ? '' : words;
        final changed = await sql.update(
          'UPDATE message_marks SET is_pinned = 1, pinned_by = ?, pinned_ts = ?, preview = ? '
          'WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
          [by, ts, preview, ...scope, '$id'],
        );
        if (changed == 0) {
          await sql.insert(
            'INSERT INTO message_marks(org_id, user_id, conv_id, msg_id, is_pinned, pinned_by, pinned_ts, preview) '
            'VALUES(?,?,?,?,1,?,?,?)',
            [...scope, '$id', by, ts, preview],
          );
        }
      }
      await _dropEmpty(sql, org, me);
    });
    await load();
  }

  Future<void> _applySaved(
    String org,
    String me,
    Map<String, dynamic> data,
  ) async {
    final list = data['ids'];
    if (list is! List) return;
    final scope = [org, me, _conv];
    await _db.transaction((sql) async {
      final deleted = await _deletedAmong(sql, org, me);
      await sql.update(
        'UPDATE message_marks SET is_saved = 0 WHERE org_id = ? AND user_id = ? AND conv_id = ? AND is_saved = 1',
        scope,
      );
      for (final raw in list) {
        final id = numericId(raw);
        if (id == null || deleted.contains('$id')) continue;
        await _setConfirmedSaved(sql, scope, '$id', true);
      }
      await _dropEmpty(sql, org, me);
    });
    await load();
  }

  Future<void> _setConfirmedSaved(
    Sql sql,
    List<String> scope,
    String msgId,
    bool isSaved,
  ) async {
    final changed = await sql.update(
      'UPDATE message_marks SET is_saved = ? WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
      [isSaved ? 1 : 0, ...scope, msgId],
    );
    if (changed == 0 && isSaved) {
      await sql.insert(
        'INSERT INTO message_marks(org_id, user_id, conv_id, msg_id, is_saved) VALUES(?,?,?,?,1)',
        [...scope, msgId],
      );
    }
  }

  // ---- events --------------------------------------------------------------

  /// `pins_changed` for `self` re-reads the pins once for a burst;
  /// `saved_changed` sets one note; `self_deleted` drops the note's marks.
  Future<void> onEvent(Map<String, dynamic> e) async {
    if (!_socket.isCurrent(e) || !_canWork) return;
    final isSd = e['type'] == 'sd_event';
    final name = isSd ? e['event'] : e['type'];
    final data = isSd
        ? ((e['data'] as Map?)?.cast<String, dynamic>() ?? const {})
        : e;
    switch (name) {
      case MarkEvents.pinsChanged:
        if (idText(data['conv']) == _conv) requestPins();
      case MarkEvents.savedChanged:
        await _onSavedChanged(data);
      case MarkEvents.selfDeleted:
        await _forget(idText(data['messageId']));
    }
  }

  Future<void> _onSavedChanged(Map<String, dynamic> data) async {
    final id = numericId(data['id']);
    final org = _org;
    final me = _me;
    if (id == null || org == null || me == null) return;
    final isSaved = data['saved'] == true;
    await _db.transaction((sql) async {
      final deleted = await _deletedAmong(sql, org, me);
      if (isSaved && deleted.contains('$id')) return;
      await _setConfirmedSaved(sql, [org, me, _conv], '$id', isSaved);
      await _dropEmpty(sql, org, me);
    });
    await load();
  }

  /// A deleted note drops its marks and any wish that waits for it.
  Future<void> _forget(String msgId) async {
    final org = _org;
    final me = _me;
    if (msgId.isEmpty || org == null || me == null) return;
    await _db.update(
      'DELETE FROM message_marks WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ?',
      [org, me, _conv, msgId],
    );
    await load();
  }
}
