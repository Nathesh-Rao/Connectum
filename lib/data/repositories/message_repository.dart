import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/errors/run_guarded.dart';
import '../../core/log/safe.dart';
import '../../core/utils/attachment_tag.dart';
import '../db/app_database.dart';
import '../models/ids.dart';
import '../models/message.dart';
import '../models/outbox_entry.dart';
import '../models/self_conversation.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';
import '../e2e/e2e_crypto.dart';
import '../e2e/e2e_models.dart';
import 'e2e_repository.dart';
import 'encryption_policy.dart';
import '../../core/log/app_log.dart';

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

class _HeldSelf {
  const _HeldSelf({
    required this.org,
    required this.user,
    required this.event,
    required this.timer,
  });

  final String org;
  final String user;
  final Map<String, dynamic> event;
  final Timer timer;
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

class MessageRepository extends GetxService with WidgetsBindingObserver {
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

  /// A `self_message` that may be the echo of a note this phone just sent,
  /// held (by its server id) until the matching `self_ack` or the timer.
  final _heldSelf = <String, _HeldSelf>{};

  /// How long such an echo is held before it counts as a note of another
  /// device. The timer is replaceable so a test can fire it by hand.
  static const selfHold = Duration(seconds: 3);
  @visibleForTesting
  Timer Function(Duration, void Function()) holdTimer = Timer.new;

  /// The device clock (no server time offset is tracked). Replaceable in a
  /// test.
  @visibleForTesting
  int Function() clock = () => DateTime.now().millisecondsSinceEpoch;

  /// Server time minus the device clock, from the `now` of the last history
  /// answer; zero until one arrived. Only the chat edit window uses it.
  int _serverSkewMs = 0;

  int get _serverNow => clock() + _serverSkewMs;

  final _notices = StreamController<String>.broadcast();

  /// Short plain-words lines about a note command that ended without the
  /// person asking (an edit that came too late, a delete that failed).
  Stream<String> get notices => _notices.stream;

  static const cantEditYet = "Can't edit this note yet";
  static const tooOldToEdit = 'Too old to edit';
  static const couldNotEditMessage = "Couldn't edit this message";

  /// The server's `CHAT_EDIT_WINDOW_SEC` (900 s) for direct chats and groups,
  /// counted from the message's server time to the moment the server
  /// receives the edit.
  static const chatEditWindow = Duration(minutes: 15);
  static const couldNotEdit = "Couldn't edit this note";
  static const couldNotDelete = "Couldn't delete the note";

  void _learnServerTime(Object? serverNow) {
    final now = serverNow is int ? serverNow : int.tryParse('$serverNow');
    if (now != null && now > 0) _serverSkewMs = now - clock();
  }

  void _notify(String text) {
    if (!_notices.isClosed) _notices.add(text);
  }

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
          .catchError(
            (Object err, StackTrace s) => _logDropped(err, s, 'message event'),
          );
    }, onError: streamOnError('message_repository'));
    _socket.listenOnline('messages', _onOnline);
    _e2e.unlockRequests.listen((_) {
      fireAndLog('messages.unlock', _unlockLocked);
      fireAndLog('messages.self_wake', _wakeSelfNotes);
    }, onError: streamOnError('message_repository'));
    WidgetsBinding.instance.addObserver(this);
    _e2e.registrations.listen((_) {
      fireAndLog('messages.reopen', reopenNoDevice);
      fireAndLog('messages.self_wake', _wakeSelfNotes);
    }, onError: streamOnError('message_repository'));
    _conversations.receiptsChanged.listen(
      applyReceipts,
      onError: streamOnError('message_repository'),
    );
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
      _clearHeldSelf();
      _lists.keys.toList().forEach(_reload);
      _scheduleDecrypt();
    });
    _scheduleDecrypt();
  }

  /// A note that waits for encryption is tried again when the app comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      fireAndLog('messages.self_wake', _wakeSelfNotes);
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  /// Completes when every envelope held so far has been tried, so a read
  /// that follows sees the opened text (the AI transcript needs it).
  Future<void> settleDecrypt() => _decrypting;

  void _scheduleDecrypt() {
    _decrypting = _decrypting
        .then((_) => _decryptPending())
        .catchError(
          (Object err, StackTrace s) => _logDropped(err, s, 'decrypt pass'),
        );
  }

  /// The queue keeps going after a failed step; the failure is logged and
  /// reported, never dropped silently.
  void _logDropped(Object e, StackTrace s, String reason) =>
      runGuarded(() => Future<void>.error(e, s), reason: reason);

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
    if (SelfConversation.isSelf(m.convId)) return _deleteSelf(m);
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
      "ORDER BY CASE WHEN msg_id LIKE 'temp-%' THEN 1 ELSE 0 END, ts, local_seq, LENGTH(msg_id), msg_id",
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
    if (SelfConversation.isSelf(convId)) {
      // No list row: the thread's facts come from its own notes.
      final own = await _db.query(
        'SELECT COUNT(*) AS n, COALESCE(SUM(is_encrypted_unsupported), 0) AS e FROM messages '
        "WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id NOT LIKE 'temp-%'",
        [_org, _me, convId],
      );
      return ThreadFacts(
        isE2e: own.isNotEmpty && intOf(own.first['e']) > 0,
        hasHistory: own.isNotEmpty && intOf(own.first['n']) > 0,
      );
    }
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
    final isSelf = SelfConversation.isSelf(convId);
    final body = text.trim();
    if (body.isEmpty) return SendResult.invalid;
    if (body.length > SelfConversation.maxLength) return SendResult.tooLong;
    if (isSelf && isCommandLike(body)) {
      // `#` lines run as commands and are never stored as notes.
      lastBlock = _noCommands;
      return SendResult.blocked;
    }
    if (convId == 'global' && body.startsWith('/')) return SendResult.invalid;
    if (replyTo != null && replyTo.startsWith('temp-')) {
      return SendResult.invalid;
    }
    // A note is quoted only by a sent note that is still there.
    if (isSelf && replyTo != null && !await _isReplyTarget(replyTo)) {
      return SendResult.invalid;
    }
    // A send that can never work (no encryption set up by the peer, a changed
    // key, an encrypted group) is refused here; one that may work later is
    // queued and decided again when it goes out.
    final facts = await _facts(convId);
    final gate = await _policy.decideSend(convId, facts, isLookup: false);
    // A note that waits for encryption is queued, not refused: it goes out
    // encrypted when the keys are ready and never as plain text.
    final waitsForKeys = isSelf && gate.isSetupMissing;
    if (gate.isBlocked && !gate.isTransient && !waitsForKeys) {
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
    AppLog.i(
      'outbox',
      'queued ${replyTo == null ? 'message' : 'reply'} cid=$cid encrypted=$isSecure',
    );
    await _db.transaction((sql) async {
      // My Work Space has no list row.
      if (!isSelf) await ConversationRepository.ensure(sql, org, user, convId);
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
      if (!isSelf) {
        await sql.update(
          'UPDATE conversations SET last_text = ?, last_ts = ?, last_from = ? WHERE org_id = ? AND user_id = ? AND conv_id = ?',
          [body, now, user, org, user, convId],
        );
      }
    });
    lastCid = cid;
    await _reload(convId);
    await _conversations.reload();
    fireAndLog('message_repository', () => flush());
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
    if (SelfConversation.isSelf(message.convId)) {
      return _editSelf(message, body);
    }
    if (!message.isMine || message.isDeleted || message.kind != 'chat') {
      return false;
    }
    if (message.convId.startsWith('host:')) return false;
    if (message.isLocalTemp) {
      if (message.isEncrypted) return false;
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
      if (!canEditChat(message)) {
        if (_isChatEditCandidate(message) && !_isInChatWindow(message.ts)) {
          _notify(tooOldToEdit);
        }
        return false;
      }
      if (message.isEncrypted && isCommandLike(body)) {
        lastBlock = _noCommands;
        return false;
      }
      if (body == message.text) return true;
      return _queueEdit(message, body, ts: message.ts);
    }
    await _reload(message.convId);
    fireAndLog('message_repository', () => flush());
    return true;
  }

  Future<void> retry(String msgId) async {
    AppLog.i('outbox', 'retry requested by the user');
    final org = _org;
    final user = _me;
    if (org == null || user == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - _cidMemory.inMilliseconds;
    await _db.transaction((sql) async {
      // A note too old for the server to know its client id is sent again as
      // a new note: a new id, and the time of the new attempt.
      final fresh = newCid();
      final renewed = await sql.update(
        'UPDATE outbox SET cid = ?, created_ts = ? WHERE org_id = ? AND user_id = ? AND ref_id = ? '
        "AND conv_id = 'self' AND status = 'failed' AND (created_ts < ? OR first_attempt_ts < ?)",
        [fresh, now, org, user, msgId, cutoff, cutoff],
      );
      if (renewed > 0) {
        await sql.update(
          "UPDATE messages SET cid = ?, ts = ?, local_seq = ? WHERE org_id = ? AND user_id = ? AND msg_id = ? AND conv_id = 'self'",
          [fresh, now, now, org, user, msgId],
        );
      }
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
    fireAndLog('message_repository', () => flush());
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

  // ---- notes: edit, delete, reply -----------------------------------------

  /// An edit or a delete: a command with no client id and no ack.
  static bool _isCommandOnly(String kind) => kind == 'edit' || kind == 'delete';

  Future<bool> _isReplyTarget(String id) async {
    if (numericId(id) == null) return false;
    final rows = await _db.query(
      'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND conv_id = ? AND msg_id = ? AND is_deleted = 0',
      [_org, _me, SelfConversation.id, id],
    );
    return rows.isNotEmpty;
  }

  /// True when [m] can be quoted: a sent note, not deleted, not locked.
  bool canReplyToNote(Message m) =>
      SelfConversation.isSelf(m.convId) &&
      !m.isLocalTemp &&
      numericId(m.msgId) != null &&
      m.status != MessageStatus.failed &&
      !m.isDeleted &&
      !m.isEncryptedUnsupported;

  /// True when [m] can be edited now: my sent note, readable and not already
  /// being edited. Notes have no age limit ([SelfConversation.hasEditWindow]).
  bool canEditNote(Message m) =>
      canReplyToNote(m) &&
      m.isMine &&
      m.kind == 'chat' &&
      !m.isEditPending &&
      AttachmentTag.parse(m.text) == null &&
      SelfConversation.isInEditWindow(m.ts, clock());

  bool _isInChatWindow(int ts) =>
      _serverNow - ts <= chatEditWindow.inMilliseconds;

  /// What decides Edit apart from the age: my own readable text message that
  /// the server has, in a direct chat, group or the general room.
  bool _isChatEditCandidate(Message m) {
    if (SelfConversation.isSelf(m.convId) || m.convId.startsWith('host:')) {
      return false;
    }
    final kind = ConversationRepository.kindOf(m.convId);
    return (kind == 'dm' || kind == 'group' || kind == 'global') &&
        m.isMine &&
        m.kind == 'chat' &&
        !m.isDeleted &&
        !m.isLocalTemp &&
        numericId(m.msgId) != null &&
        (m.status == MessageStatus.sent ||
            m.status == MessageStatus.delivered ||
            m.status == MessageStatus.read) &&
        !m.isEditPending &&
        !m.isEncryptedUnsupported &&
        m.text.trim().isNotEmpty &&
        AttachmentTag.parse(m.text) == null;
  }

  /// True when [m] can be edited now: the web's rule (my own text message,
  /// not failed, deleted, unreadable or a file) and the server's 15 minutes.
  bool canEditChat(Message m) =>
      _isChatEditCandidate(m) && _isInChatWindow(m.ts);

  bool _isEditable(OutboxEntry e) {
    final ts = e.payload['noteTs'] ?? e.payload['msgTs'];
    if (ts is! int) return true;
    return SelfConversation.isSelf(e.convId)
        ? SelfConversation.isInEditWindow(ts, clock())
        : _isInChatWindow(ts);
  }

  /// Queues an edit of a sent note: the new text shows at once with a clock
  /// until the server confirms, and the old state is kept to put back.
  Future<bool> _editSelf(Message message, String body) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return false;
    if (!canEditNote(message)) {
      if (SelfConversation.hasEditWindow &&
          message.isMine &&
          !message.isEditPending) {
        _notify(cantEditYet);
      }
      return false;
    }
    if (isCommandLike(body)) {
      lastBlock = _noCommands;
      return false;
    }
    if (body.length > SelfConversation.maxLength) {
      lastBlock = SelfConversation.tooLongText;
      return false;
    }
    if (body == message.text) return true;
    return _queueEdit(message, body, ts: message.ts);
  }

  /// Queues an edit: the new text shows at once with a clock until the server
  /// answers, and the old state is kept to put back.
  Future<bool> _queueEdit(
    Message message,
    String body, {
    required int ts,
  }) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return false;
    final isSelf = SelfConversation.isSelf(message.convId);
    final rows = await _db.query(
      'SELECT text, plaintext, decrypt_state, is_encrypted_unsupported, edited_ts FROM messages '
      'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [org, user, message.msgId],
    );
    if (rows.isEmpty) return false;
    final row = rows.first;
    final isSealed = message.isEncrypted;
    final now = clock();
    AppLog.i('outbox', 'queued edit id=${message.msgId}');
    await _db.transaction((sql) async {
      await sql.insert(
        'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts) '
        "VALUES(?,?,?,'edit',?,?,'pending',?)",
        [
          org,
          user,
          message.convId,
          jsonEncode({
            'text': body,
            'prevText': message.text,
            isSelf ? 'noteTs' : 'msgTs': ts,
            'prev': {
              'text': row['text'],
              'plaintext': row['plaintext'],
              'decrypt': row['decrypt_state'],
              'enc': intOf(row['is_encrypted_unsupported']),
              'editedTs': row['edited_ts'],
            },
          }),
          message.msgId,
          now,
        ],
      );
      await sql.update(
        'UPDATE messages SET ${isSealed ? 'plaintext' : 'text'} = ?, fail_reason = ? '
        'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [body, SelfConversation.editPending, org, user, message.msgId],
      );
    });
    await _reload(message.convId);
    fireAndLog('message_repository', () => flush());
    return true;
  }

  /// Removes a sent note at once and queues `/delete self`. Repeating a
  /// delete is safe, so it goes out under the usual retry rules; if it
  /// finally fails the note comes back.
  Future<DeleteResult> _deleteSelf(Message m) async {
    final org = _org;
    final user = _me;
    if (org == null || user == null) return DeleteResult.failed;
    if (numericId(m.msgId) == null) return DeleteResult.notSupported;
    AppLog.i('outbox', 'queued delete id=${m.msgId}');
    await _db.transaction((sql) async {
      final queued = await sql.query(
        'SELECT 1 FROM outbox WHERE org_id = ? AND user_id = ? AND conv_id = ? AND kind = ? AND ref_id = ? '
        "AND status IN ('pending','sending')",
        [org, user, SelfConversation.id, 'delete', m.msgId],
      );
      if (queued.isEmpty) {
        // An edit still waiting for a note that is going away is dropped.
        await sql.update(
          "DELETE FROM outbox WHERE org_id = ? AND user_id = ? AND conv_id = ? AND ref_id = ? AND kind = 'edit' AND status = 'pending'",
          [org, user, SelfConversation.id, m.msgId],
        );
        await sql.insert(
          'INSERT INTO outbox(org_id, user_id, conv_id, kind, payload_json, ref_id, status, created_ts) '
          "VALUES(?,?,?,'delete','{}',?,'pending',?)",
          [org, user, SelfConversation.id, m.msgId, clock()],
        );
      }
      await sql.update(
        'UPDATE messages SET is_deleted = 1, fail_reason = NULL WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [org, user, m.msgId],
      );
    });
    await _reload(SelfConversation.id);
    fireAndLog('message_repository', () => flush());
    return DeleteResult.deleted;
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
      "AND o.kind IN ('message','reply','edit','delete') AND o.next_attempt_ts <= ? "
      'AND NOT EXISTS (SELECT 1 FROM outbox p WHERE p.org_id = o.org_id AND p.user_id = o.user_id '
      "AND p.conv_id = o.conv_id AND p.kind IN ('message','reply','edit','delete') "
      "AND (p.status = 'sending' OR (p.status = 'pending' AND p.id < o.id AND p.next_attempt_ts > ?))) "
      'ORDER BY o.id LIMIT 1',
      [_org, _me, now, now],
    );
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  Future<void> _scheduleWake() async {
    final rows = await _db.query(
      "SELECT MIN(next_attempt_ts) AS t FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'pending' "
      "AND kind IN ('message','reply','edit','delete') AND next_attempt_ts > ?",
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

  /// A note is also stopped when it waited more than 23 hours in the outbox
  /// without ever being sent: the person sends it again as a new note.
  bool _isTooOld(OutboxEntry e) =>
      e.usesCid &&
      (_isPastCidMemory(e) ||
          (SelfConversation.isSelf(e.convId) &&
              DateTime.now().millisecondsSinceEpoch - e.createdTs >
                  _cidMemory.inMilliseconds));

  String _tooOldReason(OutboxEntry e) => SelfConversation.isSelf(e.convId)
      ? SelfConversation.tooOld
      : couldNotConfirm;

  Future<_Outcome> _send(OutboxEntry entry) async {
    AppLog.i(
      'outbox',
      'send kind=${entry.kind} cid=${entry.cid} attempt=${entry.retryCount + 1}',
    );
    final isSelf = SelfConversation.isSelf(entry.convId);
    if (entry.isUnreadable) {
      await _fail(entry, 'unreadable');
      return _Outcome.finished;
    }
    if (entry.retryCount >= _maxAttempts) {
      await _fail(entry, 'too many attempts');
      return _Outcome.finished;
    }
    if (_isTooOld(entry)) {
      await _fail(entry, _tooOldReason(entry));
      return _Outcome.finished;
    }
    if (entry.kind == 'edit' && !_isEditable(entry)) {
      // The server counts the window to the moment it receives the edit, so
      // an edit that waited too long is not sent at all (and never retried).
      await _dropSelfCommand(
        entry,
        notice: isSelf ? cantEditYet : tooOldToEdit,
      );
      return _Outcome.finished;
    }
    // The only place chat text is put on the socket. The decision is asked
    // again here, so a key change or a new device after composing is caught.
    // A delete carries no text: nothing to decide or seal.
    final decision = entry.kind == 'delete'
        ? const E2eSendDecision.plain()
        : await _policy.decideSend(entry.convId, await _facts(entry.convId));
    switch (decision.verdict) {
      case E2eSendVerdict.unknown:
        if (isSelf) return _waitForEncryption(entry);
        await _defer(entry, const Duration(seconds: 15));
        return _Outcome.deferred;
      case E2eSendVerdict.blocked:
        // A note waits (never plain) while keys or the device list are not
        // ready; it fails only on a refusal that waiting cannot fix.
        if (isSelf && (decision.isSetupMissing || decision.isTransient)) {
          return _waitForEncryption(entry);
        }
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
    if (entry.kind == 'edit' && !decision.isEncrypt && _wasSealed(entry)) {
      // An encrypted message's edit must be encrypted too (the server refuses
      // the plain one), and the new text must never leave in the clear.
      AppLog.w('outbox', 'edit of an encrypted message without encryption');
      await _dropSelfCommand(
        entry,
        notice: isSelf ? couldNotEdit : couldNotEditMessage,
      );
      return _Outcome.finished;
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
      try {
        envelope = await _e2e.seal(
          decision,
          entry.convId,
          '${entry.payload['text']}',
        );
      } catch (e, st) {
        AppLog.e(
          'message_repository',
          e,
          st,
          'encrypt ${e is E2eException ? e.code : ''}',
        );
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
      if (isSelf && envelope.length > SelfConversation.maxEnvelope) {
        // Never cut: the note is refused before it is sent.
        AppLog.w(
          'outbox',
          'note envelope too large boxes=${decision.recipients.length}',
        );
        await _fail(entry, '${E2eSendDecision.failTag}$_tooLargeNote');
        return _Outcome.finished;
      }
    }
    if (envelope != null) {
      final mid = E2eCrypto.midOf(envelope);
      if (mid != null) {
        _sealedMids[entry.id] = mid;
        if (isSelf && !_isCommandOnly(entry.kind))
          await _rememberMid(entry, mid);
      }
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
      if (!_isCommandOnly(entry.kind)) {
        await sql.update(
          "UPDATE messages SET status = 'sending', fail_reason = NULL WHERE org_id = ? AND user_id = ? AND msg_id = ?",
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
    if (kind != 'dm' &&
        kind != 'group' &&
        kind != 'host' &&
        !SelfConversation.isSelf(convId)) {
      return null;
    }
    final target = ConversationRepository.targetOf(convId);
    final command = switch (kind) {
      'self' => '/self $text',
      'dm' => '/msg $target $text',
      'group' => '/groupmsg $target $text',
      _ => '/hostmsg $target $text',
    };
    return '/c $cid $command';
  }

  static String? _commandFor(OutboxEntry e, {String? text}) {
    text ??= '${e.payload['text']}';
    final reply = e.payload['replyTo'] as String?;
    if (SelfConversation.isSelf(e.convId)) {
      // A note has its own commands and can never fall through to the plain
      // text of the global room or a direct chat. Only a server id goes on
      // the wire as the target.
      final target = numericId(e.refId) == null ? null : e.refId;
      final quoted = reply != null && numericId(reply) != null ? reply : null;
      return switch (e.kind) {
        'message' => '/self $text',
        'reply' => quoted == null ? null : '/replyself $quoted $text',
        'edit' => target == null ? null : '/edit self $target $text',
        'delete' => target == null ? null : '/delete self $target',
        _ => null,
      };
    }
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
      if (!_isCommandOnly(e.kind)) {
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
    AppLog.w(
      'outbox',
      'failed kind=${e.kind} cid=${e.cid} retries=${e.retryCount} reason=$reason',
    );
    final isSelf = SelfConversation.isSelf(e.convId);
    if ((isSelf && _isCommandOnly(e.kind)) || e.kind == 'edit') {
      // An edit or a delete of a note, or an edit of a chat message, has no
      // retry button: the message goes back to what it was and the person is
      // told (a refusal on encryption grounds says why).
      final why = reason.startsWith(E2eSendDecision.failTag)
          ? reason.substring(E2eSendDecision.failTag.length)
          : '';
      await _dropSelfCommand(
        e,
        notice: e.kind == 'edit'
            ? (isSelf
                  ? couldNotEdit
                  : (why.isEmpty ? couldNotEditMessage : why))
            : couldNotDelete,
      );
      return;
    }
    _settle(e.id);
    _staleTries.remove(e.id);
    await _db.transaction((sql) async {
      await sql.update(
        "UPDATE outbox SET status = 'failed', last_error = ? WHERE id = ?",
        [reason, e.id],
      );
      await sql.update(
        "UPDATE messages SET status = 'failed', fail_reason = ? WHERE org_id = ? AND user_id = ? AND msg_id = ?",
        [reason, _org, _me, e.refId],
      );
    });
    await _reload(e.convId);
    fireAndLog('message_repository', () => flush());
  }

  void _onDropped() {
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    _ackTimers.clear();
    _sealedMids.clear();
    _inFlight.clear();
    // A held echo is a note of mine whatever happens next: it is added now.
    for (final id in _heldSelf.keys.toList()) {
      _enqueue('release held note', () => _releaseHeld(id));
    }
    for (final waiter in _historyWaiters.values) {
      if (!waiter.isCompleted) waiter.completeError(StateError('dropped'));
    }
  }

  Future<void> _onAckTimeout(int outboxId) async {
    final entry = _inFlight[outboxId];
    if (entry == null || !_socket.isOnline) return;
    _settle(outboxId);
    await _recover(entry, countAttempt: true);
    fireAndLog('message_repository', () => flush());
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
        "SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND status = 'sending' AND kind IN ('message','reply','edit','delete') ORDER BY id",
        [_org, _me],
      );
      for (final row in stale) {
        await _recover(OutboxEntry.fromRow(row), countAttempt: false);
      }
      await _wakeSelfNotes();
      await flush();
      await _syncAll();
      await syncSelf();
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
    if (_isCommandOnly(entry.kind)) {
      await _backToPending(entry, countAttempt: countAttempt);
    } else if (!entry.usesCid) {
      await _reconcileByText(entry);
    } else if (_isTooOld(entry)) {
      await _fail(entry, _tooOldReason(entry));
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

  Future<_History?> _fetchHistory(
    String convId, {
    String? before,
    ({String after, int since})? delta,
  }) async {
    final key = delta != null
        ? 'delta:$convId'
        : before == null
        ? convId
        : 'older:$convId';
    final existing = _historyWaiters[key];
    if (existing != null) {
      return existing.future.then<_History?>((h) => h).catchError((
        Object e,
        StackTrace st,
      ) {
        AppLog.w('message_repository', 'history wait ${e.runtimeType}');
        return null;
      });
    }
    final kind = ConversationRepository.kindOf(convId);
    final target = ConversationRepository.targetOf(convId);
    final waiter = Completer<_History>();
    _historyWaiters[key] = waiter;
    try {
      final scope = kind == 'global' || kind == 'self' ? kind : '$kind $target';
      final sent = await _socket.sendCommand(
        delta != null
            ? '/history $scope delta ${delta.after} ${delta.since}'
            : before == null
            ? '/history $scope'
            : '/history $scope before $before',
      );
      if (!sent) return null;
      return await waiter.future.timeout(const Duration(seconds: 10));
    } catch (e, st) {
      AppLog.e('message_repository', e, st, 'history');
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
      case 'self_message':
        await _onSelfMessage(e);
      case 'self_edited':
        await _onSelfEdited(e);
      case 'self_deleted':
        await _onSelfDeleted(e);
      case 'self_ack':
        await _onSelfAck(e);
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
        await _onSelfDeleteDenied(e);
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
        if (event is String && _selfEvents.contains(event)) {
          await _handle({
            ...((e['data'] as Map?)?.cast<String, dynamic>() ?? {}),
            'type': event,
          });
        }
        if (event == 'receipt') {
          await _onReceipt((e['data'] as Map?)?.cast<String, dynamic>() ?? {});
        }
        if (event == 'submission_rejected') {
          await _onRejected((e['data'] as Map?)?.cast<String, dynamic>() ?? {});
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
      entry = await _sendByCid(cid);
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
    fireAndLog('message_repository', () => flush());
  }

  /// The send still waiting for its answer under this client id.
  Future<OutboxEntry?> _sendByCid(String cid) async {
    final rows = await _db.query(
      'SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND cid = ? '
      "AND kind IN ('message','reply') AND status IN ('sending','pending') ORDER BY id LIMIT 1",
      [_org, _me, cid],
    );
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  Future<void> _adopt(
    OutboxEntry entry,
    String serverId,
    int ts, {
    bool delivered = false,
    bool moveCursor = true,
  }) async {
    AppLog.i('outbox', 'sent kind=${entry.kind} cid=${entry.cid}');
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
    final sends =
        _inFlight.values.where((i) => i.isSend || i.kind == 'edit').toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    _policy.onReconnected();
    if (sends.isEmpty) return;
    final entry = sends.first;
    final peer = ConversationRepository.targetOf(entry.convId);
    final isGroup = entry.convId.startsWith('group:');
    if (code == 'bad_envelope' &&
        (SelfConversation.isSelf(entry.convId) || entry.kind == 'edit')) {
      // A box the server does not accept (a device that is gone or new):
      // the device lists are read again, then one more try.
      if (isGroup) _e2e.invalidateGroup(peer);
      await _retrySealed(entry, [if (entry.convId.startsWith('dm:')) peer]);
      return;
    }
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
          (conv.isEmpty ||
              entry.convId.toLowerCase() == conv ||
              (SelfConversation.isSelf(entry.convId) &&
                  conv == E2eCrypto.selfLabel(_me ?? '')))) {
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
    await _retrySealed(entry, [if (users is List) ...users.map((u) => '$u')]);
  }

  /// Forgets the device lists, then sends again under the same `cid` with a
  /// new envelope: at most [_maxStaleRetries] times for a chat, once for a
  /// note. After that the message fails (never plain text).
  Future<void> _retrySealed(OutboxEntry entry, List<String> users) async {
    _e2e.invalidate([...users, _me ?? '']);
    final tries = (_staleTries[entry.id] ?? 0) + 1;
    final most = SelfConversation.isSelf(entry.convId) || entry.kind == 'edit'
        ? 1
        : _maxStaleRetries;
    if (tries > most) {
      if (kDebugMode) debugPrint('e2e: stale devices, giving up');
      await _fail(entry, E2eSendDecision.staleFailure);
      return;
    }
    _staleTries[entry.id] = tries;
    if (kDebugMode) debugPrint('e2e: stale devices, resend $tries');
    _settle(entry.id);
    await _backToPending(entry, countAttempt: false);
    fireAndLog('message_repository', () => flush());
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

  /// `edited`, `dm_edited` and `group_edited`. An edit I sent from this phone
  /// is settled by its own echo (same text, or the same envelope `mid`) and
  /// the text I typed stays on screen: no second read of the envelope, no
  /// flicker; a repeat of the event changes nothing. An edit by another
  /// person or device replaces the text and is opened like any envelope.
  Future<void> _onEdited(Map<String, dynamic> e) async {
    final id = idText(e['messageId']);
    if (id.isEmpty) return;
    final text = idText(e['text']);
    final isEnvelope = E2eCrypto.isEnvelope(text);
    final editedTs = e['editedTs'] == null ? null : intOf(e['editedTs']);
    final rows = await _db.query(
      'SELECT is_mine, edited_ts, decrypt_state, plaintext, text, conv_id FROM messages '
      'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [_org, _me, id],
    );
    if (rows.isEmpty) return;
    final row = rows.first;
    final convId = idText(row['conv_id']);
    if (SelfConversation.isSelf(convId)) return;
    final own = await _ownEditFor(id, text, isEnvelope);
    if (own != null) {
      _settle(own.id);
      await _db.transaction((sql) async {
        await sql.update('DELETE FROM outbox WHERE id = ?', [own.id]);
        await sql.update(
          'UPDATE messages SET text = ?, edited_ts = ?, fail_reason = NULL, '
          "plaintext = CASE WHEN ? = 1 THEN ? ELSE NULL END, decrypt_state = CASE WHEN ? = 1 THEN 'ok' ELSE NULL END, "
          'is_encrypted_unsupported = ? '
          'WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [
            text,
            editedTs,
            isEnvelope ? 1 : 0,
            '${own.payload['text']}',
            isEnvelope ? 1 : 0,
            isEnvelope ? 1 : 0,
            _org,
            _me,
            id,
          ],
        );
      });
      await _reload(convId);
      fireAndLog('message_repository', () => flush());
      return;
    }
    final isSameEdit =
        editedTs != null &&
        row['edited_ts'] != null &&
        intOf(row['edited_ts']) == editedTs;
    final isMineOpened =
        intOf(row['is_mine']) == 1 &&
        row['decrypt_state'] == 'ok' &&
        row['plaintext'] != null;
    if (isSameEdit && (isEnvelope ? isMineOpened : row['text'] == text)) {
      return;
    }
    await _db.update(
      'UPDATE messages SET text = ?, edited_ts = ?, fail_reason = NULL, is_encrypted_unsupported = ?, '
      'decrypt_state = ?, plaintext = NULL WHERE org_id = ? AND user_id = ? AND msg_id = ?',
      [
        text,
        editedTs,
        isEnvelope ? 1 : 0,
        isEnvelope ? 'pending' : null,
        _org,
        _me,
        id,
      ],
    );
    if (isEnvelope) _scheduleDecrypt();
    await _reloadAll();
  }

  // ---- My Work Space notes (receive only) -------------------------------------

  static const _selfEvents = {
    'self_message',
    'self_edited',
    'self_deleted',
    'self_ack',
  };

  /// The notes of My Work Space, read from SQLite (empty offline until the
  /// first sync) and kept up to date in place. The network fills it in the
  /// background through [syncSelf].
  Future<RxList<Message>> openSelf() async {
    final list = await open(SelfConversation.id);
    fireAndLog('message_repository.self', syncSelf);
    return list;
  }

  /// Newest page of the person's own conversation (and the gap check), then
  /// what changed since the last answer (edits and deletes of older notes).
  /// The same history reader as every chat.
  Future<void> syncSelf() async {
    final org = _org;
    final user = _me;
    if (org == null || user == null || !_socket.isOnline) return;
    try {
      final saved = await _db.query(
        'SELECT last_server_id, last_history_now FROM sync_cursor WHERE org_id = ? AND user_id = ? AND conv_id = ?',
        [org, user, SelfConversation.id],
      );
      final lastId = saved.isEmpty
          ? null
          : numericId(saved.first['last_server_id']);
      final since = saved.isEmpty ? 0 : intOf(saved.first['last_history_now']);
      await _syncConversation(SelfConversation.id);
      await _reopenSelfLocked();
      if (_org != org || _me != user || !_socket.isOnline) return;
      if (lastId == null || since <= 0) return;
      await _fetchHistory(
        SelfConversation.id,
        delta: (after: '$lastId', since: since),
      );
    } catch (e, st) {
      AppLog.e('message_repository', e, st, 'self sync');
    }
  }

  /// A locked note is never dropped: after every sync the ones that failed
  /// for a reason that may have passed (keys not ready, a sender device not
  /// known yet, a directory lookup that failed) are opened again. A note with
  /// no box for this phone stays locked until its envelope changes.
  Future<void> _reopenSelfLocked() async {
    final changed = await _db.update(
      "UPDATE messages SET decrypt_state = 'pending', plaintext = NULL "
      "WHERE org_id = ? AND user_id = ? AND conv_id = ? AND decrypt_state = 'cant_decrypt' "
      "AND (plaintext IN ('no_device', 'unknown_sender_device') OR plaintext LIKE 'directory_%')",
      [_org, _me, SelfConversation.id],
    );
    if (changed > 0) _scheduleDecrypt();
  }

  /// A note of mine, typed on this or another device. Added once by its
  /// server id; a repeat (or the same note from history) changes nothing.
  ///
  /// The server pushes the live copy BEFORE it answers the sender with
  /// `self_ack`, and the copy carries no client id. While this phone has a
  /// note in flight, an unknown id is therefore held for [selfHold]: if a
  /// `self_ack` with that id arrives, the held copy is the echo of my own note
  /// and is dropped (the pending row takes the id); otherwise it is a note of
  /// another device and is added. Text is never compared.
  Future<void> _onSelfMessage(Map<String, dynamic> e) async {
    final org = _org;
    final user = _me;
    final id = idText(e['id']);
    if (org == null || user == null || id.isEmpty) return;
    if (_heldSelf.containsKey(id) || await _hasMessage(id)) return;
    final mine = await _selfSendByMid(idText(e['text']));
    if (mine != null) {
      // My own encrypted note, known by its envelope id: no hold is needed.
      AppLog.i('outbox', 'self note matched by mid');
      await _adopt(mine, id, intOf(e['ts']));
      fireAndLog('message_repository', () => flush());
      return;
    }
    if (!_hasSelfInFlight) {
      await _insertSelf(e);
      return;
    }
    _heldSelf[id] = _HeldSelf(
      org: org,
      user: user,
      event: e,
      timer: holdTimer(
        selfHold,
        () => _enqueue('release held note', () => _releaseHeld(id)),
      ),
    );
  }

  bool get _hasSelfInFlight => _inFlight.values.any(
    (i) => i.isSend && SelfConversation.isSelf(i.convId),
  );

  Future<bool> _hasMessage(String id) async => (await _db.query(
    'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
    [_org, _me, id],
  )).isNotEmpty;

  Future<void> _insertSelf(Map<String, dynamic> e) async {
    final org = _org;
    final user = _me;
    final id = idText(e['id']);
    if (org == null || user == null || id.isEmpty) return;
    await _db.transaction((sql) async {
      final known = await sql.query(
        'SELECT 1 FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
        [org, user, id],
      );
      if (known.isNotEmpty) return;
      await _upsert(sql, SelfConversation.id, {...e, 'from': user});
      await _setCursor(sql, SelfConversation.id, id);
    });
    await _reload(SelfConversation.id);
  }

  /// The hold ran out (or the connection dropped): the held copy is added as
  /// a note, unless the person or organisation changed in between.
  Future<void> _releaseHeld(String id) async {
    final held = _heldSelf.remove(id);
    if (held == null) return;
    held.timer.cancel();
    if (_org != held.org || _me != held.user) return;
    await _insertSelf(held.event);
  }

  void _clearHeldSelf() {
    for (final held in _heldSelf.values) {
      held.timer.cancel();
    }
    _heldSelf.clear();
  }

  /// Runs [job] in event order and logs (never rethrows) a failure.
  void _enqueue(String reason, Future<void> Function() job) {
    _queue = _queue
        .then((_) => job())
        .catchError((Object err, StackTrace s) => _logDropped(err, s, reason));
  }

  /// The server kept a note of mine. Its client id finds the pending row,
  /// which takes the server id and time and becomes `sent` (a note has no
  /// recipient, so the answer's `delivered` never shows ticks, as on the
  /// web). A repeat (`duplicate: true`) is the same answer again. An answer
  /// for a client id this phone does not know is ignored.
  Future<void> _onSelfAck(Map<String, dynamic> e) async {
    final id = idText(e['id']);
    final cid = e['cid'];
    final entry = cid is String && cid.isNotEmpty
        ? await _sendByCid(cid)
        : null;
    if (entry == null || !SelfConversation.isSelf(entry.convId) || id.isEmpty) {
      AppLog.d('message_repository', 'self_ack for a note not in the outbox');
      // A copy held for this id is then a note like any other.
      await _releaseHeld(id);
      return;
    }
    final held = _heldSelf.remove(id);
    held?.timer.cancel();
    await _adopt(entry, id, intOf(e['ts']), moveCursor: e['duplicate'] != true);
    fireAndLog('message_repository', () => flush());
  }

  /// A note that waits for encryption says so until it goes out. After
  /// [SelfConversation.setupAfter] the line asks the person to set encryption
  /// up. The note stays queued, never plain, until the 23 hour stop.
  Future<_Outcome> _waitForEncryption(OutboxEntry entry) async {
    final waited = Duration(milliseconds: clock() - entry.createdTs);
    final isLong = waited >= SelfConversation.setupAfter;
    final reason = isLong
        ? SelfConversation.waitingForSetup
        : SelfConversation.waitingForEncryption;
    final changed = await _db.update(
      "UPDATE messages SET fail_reason = ? WHERE org_id = ? AND user_id = ? AND msg_id = ? AND status = 'pending' "
      'AND (fail_reason IS NULL OR fail_reason != ?)',
      [reason, _org, _me, entry.refId, reason],
    );
    if (changed > 0) {
      if (isLong) {
        AppLog.w('outbox', 'note waits for encryption, setup asked');
      }
      await _reload(entry.convId);
    }
    // Events wake the note at once; the timer is the slow fallback, and the
    // moment the line has to change.
    var wait = SelfConversation.waitFallback;
    if (!isLong) {
      final left = SelfConversation.setupAfter - waited;
      if (left < wait) wait = left + const Duration(seconds: 1);
    }
    await _defer(entry, wait);
    return _Outcome.deferred;
  }

  bool _wasSealed(OutboxEntry entry) {
    final prev = entry.payload['prev'];
    return prev is Map && prev['enc'] == 1;
  }

  static const _tooLargeNote = 'That note is too large to send securely';

  /// The `mid` of every envelope sealed for a note is kept with its outbox
  /// entry, so a copy that comes back (a live frame or history) is known as
  /// mine even when the ack was lost, a retry sealed a new envelope, or the
  /// app restarted.
  Future<void> _rememberMid(OutboxEntry entry, String mid) async {
    final known = entry.payload['mids'];
    final mids = <String>[if (known is List) ...known.map((m) => '$m')];
    if (mids.contains(mid)) return;
    mids.add(mid);
    entry.payload['mids'] = mids;
    await _db.update('UPDATE outbox SET payload_json = ? WHERE id = ?', [
      jsonEncode(entry.payload),
      entry.id,
    ]);
  }

  /// My own note this envelope belongs to (matched by its `mid`, never by
  /// text), if one is still waiting for its answer. A plain note has no `mid`
  /// and is matched only by its server id.
  Future<OutboxEntry?> _selfSendByMid(String text) async {
    if (!E2eCrypto.isEnvelope(text)) return null;
    final mid = E2eCrypto.midOf(text);
    if (mid == null || mid.isEmpty) return null;
    final rows = await _db.query(
      'SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND conv_id = ? '
      "AND kind IN ('message','reply') AND status IN ('sending','pending','failed') ORDER BY id",
      [_org, _me, SelfConversation.id],
    );
    for (final row in rows) {
      final entry = OutboxEntry.fromRow(row);
      final mids = entry.payload['mids'];
      if ((mids is List && mids.any((m) => '$m' == mid)) ||
          _sealedMids[entry.id] == mid) {
        return entry;
      }
    }
    return null;
  }

  /// Encryption may be ready now (a new device list, keys, a reconnect): the
  /// waiting notes are tried again at once.
  Future<void> _wakeSelfNotes() async {
    await _db.update(
      "UPDATE outbox SET next_attempt_ts = 0 WHERE org_id = ? AND user_id = ? AND conv_id = 'self' "
      "AND status = 'pending' AND next_attempt_ts > 0",
      [_org, _me],
    );
    fireAndLog('message_repository', () => flush());
  }

  /// `self_edited` reaches every connection of the person, this one too. When
  /// it is the answer to the edit this phone sent, the queued entry is done and
  /// the text I typed stays on screen (no second read of the envelope, no
  /// flicker); a repeat of the same event changes nothing. An edit made on
  /// another device replaces the text and is opened like any envelope.
  Future<void> _onSelfEdited(Map<String, dynamic> e) async {
    final id = idText(e['messageId']);
    if (id.isEmpty) return;
    final text = idText(e['text']);
    final isEnvelope = text.startsWith('e2e1:');
    final editedTs = e['editedTs'] == null ? null : intOf(e['editedTs']);
    final own = await _ownEditFor(id, text, isEnvelope);
    if (own != null) {
      _settle(own.id);
      await _db.transaction((sql) async {
        await sql.update('DELETE FROM outbox WHERE id = ?', [own.id]);
        await sql.update(
          'UPDATE messages SET text = ?, edited_ts = ?, fail_reason = NULL, '
          "plaintext = CASE WHEN ? = 1 THEN ? ELSE NULL END, decrypt_state = CASE WHEN ? = 1 THEN 'ok' ELSE NULL END, "
          'is_encrypted_unsupported = ? '
          'WHERE org_id = ? AND user_id = ? AND msg_id = ? AND conv_id = ?',
          [
            text,
            editedTs,
            isEnvelope ? 1 : 0,
            '${own.payload['text']}',
            isEnvelope ? 1 : 0,
            isEnvelope ? 1 : 0,
            _org,
            _me,
            id,
            SelfConversation.id,
          ],
        );
      });
      await _reload(SelfConversation.id);
      fireAndLog('message_repository', () => flush());
      return;
    }
    await _db.update(
      'UPDATE messages SET text = ?, edited_ts = ?, is_encrypted_unsupported = ?, decrypt_state = ?, plaintext = NULL '
      'WHERE org_id = ? AND user_id = ? AND msg_id = ? AND conv_id = ?',
      [
        text,
        editedTs,
        isEnvelope ? 1 : 0,
        isEnvelope ? 'pending' : null,
        _org,
        _me,
        id,
        SelfConversation.id,
      ],
    );
    if (isEnvelope) _scheduleDecrypt();
    await _reload(SelfConversation.id);
  }

  /// The queued edit this event answers: same note, and the same text (plain)
  /// or the same envelope `mid` (sealed).
  Future<OutboxEntry?> _ownEditFor(
    String id,
    String text,
    bool isEnvelope,
  ) async {
    final entry = await _entryOf('edit', id);
    if (entry == null) return null;
    if (isEnvelope) {
      final mid = E2eCrypto.midOf(text);
      return mid != null && mid == _sealedMids[entry.id] ? entry : null;
    }
    return '${entry.payload['text']}' == text ? entry : null;
  }

  /// The edit or delete of a note still waiting for its answer, if any.
  Future<OutboxEntry?> _selfEntry(String kind, String refId) async =>
      _entryOf(kind, refId, convId: SelfConversation.id);

  /// The queued or sent [kind] command for message [refId], in [convId] or
  /// (when null) any conversation.
  Future<OutboxEntry?> _entryOf(
    String kind,
    String refId, {
    String? convId,
  }) async {
    final rows = await _db.query(
      'SELECT * FROM outbox WHERE org_id = ? AND user_id = ? AND kind = ? AND ref_id = ? '
      "${convId == null ? '' : 'AND conv_id = ? '}AND status IN ('sending','pending') ORDER BY id LIMIT 1",
      [_org, _me, kind, refId, ?convId],
    );
    return rows.isEmpty ? null : OutboxEntry.fromRow(rows.first);
  }

  /// `self_deleted` reaches every connection, this one too. The note is marked
  /// deleted (the My Work Space thread does not draw it); my own queued delete
  /// of it is done, and an edit still waiting for it is dropped. A repeat of
  /// the event changes nothing.
  Future<void> _onSelfDeleted(Map<String, dynamic> e) async {
    final id = idText(e['messageId']);
    if (id.isEmpty) return;
    final own = await _selfEntry('delete', id);
    if (own != null) _settle(own.id);
    await _db.transaction((sql) async {
      await sql.update(
        'UPDATE messages SET is_deleted = 1, fail_reason = NULL WHERE org_id = ? AND user_id = ? AND msg_id = ? AND conv_id = ?',
        [_org, _me, id, SelfConversation.id],
      );
      await sql.update(
        "DELETE FROM outbox WHERE org_id = ? AND user_id = ? AND conv_id = ? AND ref_id = ? AND kind IN ('delete','edit') "
        "AND status IN ('pending','failed')",
        [_org, _me, SelfConversation.id, id],
      );
      if (own != null) {
        await sql.update('DELETE FROM outbox WHERE id = ?', [own.id]);
      }
    });
    await _reload(SelfConversation.id);
    if (own != null) fireAndLog('message_repository', () => flush());
  }

  /// `delete_denied` for a note: `not_found` means it is already gone, which
  /// is what was asked; any other reason ends the delete and brings the note
  /// back.
  Future<void> _onSelfDeleteDenied(Map<String, dynamic> e) async {
    final entry = await _selfEntry('delete', idText(e['messageId']));
    if (entry == null) return;
    if (idText(e['reason']) == 'not_found') {
      await _onSelfDeleted({'messageId': entry.refId});
      return;
    }
    await _fail(entry, 'delete denied: ${idText(e['reason'])}');
  }

  /// `edit_denied` for an edit of a note. `expired` and any other refusal put
  /// the old text back and are never retried; `deleted` and `not_found` mean
  /// the note is gone.
  Future<void> _denySelfEdit(OutboxEntry entry, String reason) async {
    AppLog.w('outbox', 'edit denied reason=$reason cid=${entry.cid}');
    final isSelf = SelfConversation.isSelf(entry.convId);
    switch (reason) {
      case 'deleted':
      case 'not_found':
        await _dropSelfCommand(entry, isGone: true);
      case 'expired':
        await _dropSelfCommand(
          entry,
          notice: isSelf ? cantEditYet : tooOldToEdit,
        );
      default:
        await _dropSelfCommand(
          entry,
          notice: isSelf ? couldNotEdit : couldNotEditMessage,
        );
    }
  }

  /// Ends an edit or delete of a note without retry: the entry is removed and
  /// the note goes back to what it was before (an edit restores text, envelope
  /// and edited time; a delete shows the note again), or it is marked deleted
  /// when [isGone]. [notice] tells the person in a few words.
  Future<void> _dropSelfCommand(
    OutboxEntry e, {
    String? notice,
    bool isGone = false,
  }) async {
    AppLog.w('outbox', 'dropped kind=${e.kind} id=${e.refId} cid=${e.cid}');
    _settle(e.id);
    _staleTries.remove(e.id);
    await _db.transaction((sql) async {
      await sql.update('DELETE FROM outbox WHERE id = ?', [e.id]);
      if (isGone) {
        await sql.update(
          'UPDATE messages SET is_deleted = 1, fail_reason = NULL WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [_org, _me, e.refId],
        );
      } else if (e.kind == 'delete') {
        await sql.update(
          'UPDATE messages SET is_deleted = 0 WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [_org, _me, e.refId],
        );
      } else {
        final prev = e.payload['prev'];
        final old = prev is Map ? prev : const {};
        await sql.update(
          'UPDATE messages SET text = ?, plaintext = ?, decrypt_state = ?, is_encrypted_unsupported = ?, '
          'edited_ts = ?, fail_reason = NULL WHERE org_id = ? AND user_id = ? AND msg_id = ?',
          [
            old['text'] ?? e.payload['prevText'],
            old['plaintext'],
            old['decrypt'],
            old['enc'] == 1 ? 1 : 0,
            old['editedTs'],
            _org,
            _me,
            e.refId,
          ],
        );
      }
    });
    await _reload(e.convId);
    if (notice != null) _notify(notice);
    fireAndLog('message_repository', () => flush());
  }

  Future<void> _onEditDenied(Map<String, dynamic> e) async {
    final id = idText(e['messageId']);
    for (final entry in _inFlight.values.toList()) {
      if (entry.kind == 'edit' && entry.refId == id) {
        await _denySelfEdit(entry, idText(e['reason']));
        return;
      }
    }
    // The answer of an edit sent before a reconnect: its entry is queued.
    final queued = await _entryOf('edit', id);
    if (queued != null) await _denySelfEdit(queued, idText(e['reason']));
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
      fireAndLog(
        'message_repository',
        () => _conversations.noteDelivered(convId, id),
      );
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

  /// A rejected submission never gets a card posted, so the local card that
  /// waited for approval goes (`submission_rejected {submissionId, ...}`).
  Future<void> _onRejected(Map<String, dynamic> data) async {
    final id = idText(data['submissionId']);
    if (id.isEmpty || _org == null || _me == null) return;
    final waiting = await _db.query(
      "SELECT msg_id, conv_id, form_json FROM messages WHERE org_id = ? AND user_id = ? AND kind = 'form' "
      "AND msg_id LIKE 'temp-%' AND status = 'sent'",
      [_org, _me],
    );
    for (final w in waiting) {
      try {
        final f = jsonDecode(idText(w['form_json']));
        if (f is Map && idText(f['submissionId']) == id) {
          await _db.update(
            'DELETE FROM messages WHERE org_id = ? AND user_id = ? AND msg_id = ?',
            [_org, _me, w['msg_id']],
          );
          await _reload(idText(w['conv_id']));
        }
      } on FormatException {
        continue;
      }
    }
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
      'self' => SelfConversation.id,
      _ => '',
    };
    if (convId.isEmpty) return;
    final isSelf = SelfConversation.isSelf(convId);
    final isDelta = e['delta'] == true;
    final isOlder = e['before'] != null;
    final hasMore = e['hasMore'] == true;
    final next = e['next'] == null ? null : idText(e['next']);
    final items = ((e['list'] as List?) ?? [])
        .cast<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
    final unknown = <Map<String, dynamic>>[];
    final fresh = <int>[];
    if (isSelf) {
      // A note of mine whose ack was lost comes back in history: the pending
      // row takes its server id first (matched by the envelope `mid`).
      for (final item in items) {
        final id = idText(item['id']);
        if (id.isEmpty || await _hasMessage(id)) continue;
        final mine = await _selfSendByMid(idText(item['text']));
        if (mine == null) continue;
        AppLog.i('outbox', 'self note matched by mid in history');
        await _adopt(mine, id, intOf(item['ts']), moveCursor: false);
      }
    }
    await _db.transaction((sql) async {
      // My Work Space has no list row: it never shows in the chat list and
      // never counts as unread.
      if (!isSelf) await ConversationRepository.ensure(sql, org, user, convId);
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
      if (isDelta) {
        // Only what changed: the newest-id cursor and paging stay as they are.
        await _setCursor(sql, convId, null, now: intOf(e['now']));
        _learnServerTime(e['now']);
      } else if (isOlder) {
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
        _learnServerTime(e['now']);
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
    if (!isOlder && !isDelta && !isSelf) {
      final fromOthers = [
        for (final i in items)
          if (idText(i['from']).toLowerCase() != user.toLowerCase())
            idText(i['id']),
      ];
      if (fromOthers.isNotEmpty) {
        fireAndLog(
          'message_repository',
          () => _conversations.noteDelivered(convId, fromOthers.last),
        );
      }
    }
    await _applyReceipts(convId);
    await _reload(convId);
    await _conversations.reload();
    final waiter =
        _historyWaiters[isDelta
            ? 'delta:$convId'
            : isOlder
            ? 'older:$convId'
            : convId];
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
