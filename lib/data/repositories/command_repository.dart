import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import '../../core/debug/seed_ui.dart';
import '../models/hash_command.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/connectivity_service.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';
import 'encryption_policy.dart';
import 'message_repository.dart';

enum HashKind {
  unknown,
  needsConnection,
  blocked,
  invalid,
  error,
  directQueued,
  info,
  done,
}

/// What a `#` line or an `@user` line did, for the screen to show.
class HashResult {
  const HashResult(
    this.kind, [
    this.text = '',
    this.user = '',
    this.convId = '',
    this.cid = '',
  ]);

  final HashKind kind;
  final String text;
  final String user;
  final String convId;
  final String cid;

  /// Nothing more to fix: the screen clears the composer. Everything else
  /// keeps the typed text so it can be corrected or sent again.
  bool get isFinished =>
      kind == HashKind.directQueued ||
      kind == HashKind.info ||
      kind == HashKind.done;
}

/// The `#` command catalog and the one place a `#` line or an `@user` line is
/// turned into a send.
///
/// The server rewrites a raw `#` line into the `/command` it stands for and
/// runs it in the clear, so a raw line never leaves the phone when it would
/// message a person or group that is, or may be, encrypted. `#dm` is expanded
/// here into the normal direct-message send (outbox, cid, encryption policy).
class CommandRepository extends GetxService {
  CommandRepository(
    this._socket,
    this._store,
    this._connectivity,
    this._messages,
    this._conversations,
  );

  static const encryptedBlock = "Can't send in encrypted chats from mobile yet";
  static const _unknownBlock =
      "Can't tell yet whether that chat is encrypted. Try again in a moment";
  static const _maxLength = 2000;
  static const _formsHint = 'Use the forms button to open a form.';
  static const _replyWait = Duration(seconds: 6);
  static final _line = RegExp(r'^#([A-Za-z]\S*)\s*(.*)$', dotAll: true);

  final SocketService _socket;
  final SessionStore _store;
  final ConnectivityService _connectivity;
  final MessageRepository _messages;
  final ConversationRepository _conversations;

  final catalog = <HashCommand>[].obs;
  final isLoading = false.obs;

  String? _loadedOrg;
  bool _isFresh = false;
  Future<void>? _loading;

  static bool isHashLine(String text) => _line.hasMatch(text.trim());

  bool get isOnline => SeedUi.isActive
      ? _connectivity.state.value != AppConnectivity.offline
      : _socket.isOnline;

  @override
  void onInit() {
    super.onInit();
    _socket.onOnline.listen((_) => _isFresh = false);
    ever(_store.current, (_) => _isFresh = false);
  }

  // ---- the catalog ---------------------------------------------------------

  List<HashCommand> matching(String prefix) {
    final p = prefix.toLowerCase();
    return [
      for (final c in catalog)
        if (c.startsWithPrefix(p)) c,
    ];
  }

  HashCommand? _find(String word) {
    for (final c in catalog) {
      if (c.answersTo(word)) return c;
    }
    return null;
  }

  /// Reads the cache for this organisation, then asks the server once per
  /// connection (`/cmds` and `cmd.list`) when online.
  Future<void> ensureLoaded() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    if (SeedUi.isActive) {
      if (catalog.isEmpty) catalog.assignAll(SeedUi.commands());
      return;
    }
    final org = _store.orgId ?? '';
    if (_loadedOrg != org) {
      _loadedOrg = org;
      _isFresh = false;
      catalog.clear();
    }
    if (catalog.isEmpty) await _readCache(org);
    if (_isFresh || !_socket.isOnline) return;
    isLoading.value = true;
    try {
      await _fetch(org);
    } finally {
      isLoading.value = false;
    }
  }

  String _key(String org) => 'cmds.catalog.$org';

  Future<void> _readCache(String org) async {
    try {
      final raw = await _store.readValue(_key(org));
      if (raw == null) return;
      catalog.assignAll([
        for (final j in jsonDecode(raw) as List)
          HashCommand.fromJson(
            (j as Map).cast<String, dynamic>(),
            isCustom: j['custom'] == true,
          ),
      ]);
    } catch (_) {}
  }

  Future<void> _fetch(String org) async {
    final wait = _next('cmd_catalog', const Duration(seconds: 8));
    if (!await _socket.sendCommand('/cmds')) return;
    final event = await wait;
    if (event == null) return;
    final builtIn = [
      for (final j in (event['commands'] as List? ?? const []))
        if (j is Map) HashCommand.fromJson(j.cast<String, dynamic>()),
    ];
    if (builtIn.isEmpty) return;
    final custom = <HashCommand>[];
    try {
      final data = await _socket.sdCall('cmd.list', {});
      for (final j in (data['commands'] as List? ?? const [])) {
        if (j is! Map) continue;
        final c = HashCommand.fromJson(
          j.cast<String, dynamic>(),
          isCustom: true,
        );
        if (c.name.isNotEmpty && !builtIn.any((b) => b.answersTo(c.name))) {
          custom.add(c);
        }
      }
    } on SocketCallError catch (_) {}
    catalog.assignAll([...builtIn, ...custom]);
    _isFresh = true;
    await _store.writeValue(
      _key(org),
      jsonEncode([for (final c in catalog) c.toJson()]),
    );
  }

  Future<Map<String, dynamic>?> _next(String type, Duration timeout) {
    final done = Completer<Map<String, dynamic>?>();
    final sub = _socket.events.listen((e) {
      if (e['type'] == type && !done.isCompleted) done.complete(e);
    });
    return done.future
        .timeout(timeout, onTimeout: () => null)
        .whenComplete(sub.cancel);
  }

  // ---- running a line ------------------------------------------------------

  /// Runs a line that starts with `#` and a letter. Online only, never queued.
  Future<HashResult> run(String line) async {
    final m = _line.firstMatch(line.trim());
    if (m == null) return const HashResult(HashKind.invalid, 'Not a command.');
    final word = m.group(1)!.toLowerCase();
    final rest = m.group(2)!.trim();
    await ensureLoaded();
    final cmd = _find(word);
    if (cmd == null) {
      if (catalog.isNotEmpty) {
        return const HashResult(HashKind.unknown, 'Unknown command');
      }
      return HashResult(
        isOnline ? HashKind.error : HashKind.needsConnection,
        isOnline
            ? "Commands aren't available right now."
            : 'Needs a connection',
      );
    }
    if (!isOnline) {
      return const HashResult(HashKind.needsConnection, 'Needs a connection');
    }
    if (cmd.name == 'help' && !cmd.isCustom) return _help(rest);
    if (!cmd.isCustom && _opensForm(cmd.name)) {
      return const HashResult(HashKind.info, _formsHint);
    }
    if (cmd.name == 'dm' && !cmd.isCustom) {
      final parts = rest.split(RegExp(r'\s+'));
      final text = rest.length > parts.first.length
          ? rest.substring(parts.first.length).trim()
          : '';
      if (rest.isEmpty || text.isEmpty) {
        return HashResult(
          HashKind.invalid,
          'Usage: #${cmd.name} <user> <text>',
        );
      }
      return sendDirect(parts.first, text);
    }
    if (cmd.sendsMessage) {
      final blocked = await _blockedMessage(cmd, rest);
      if (blocked != null) return HashResult(HashKind.blocked, blocked);
    }
    if (SeedUi.isActive) return HashResult(HashKind.info, SeedUi.hashInfo(cmd));
    return _sendRaw(cmd, '#$word $rest'.trim());
  }

  static bool _opensForm(String name) =>
      name == 'tstruct' || name == 'tstruct-add' || name == 'form';

  HashResult _help(String rest) {
    final word = rest.split(RegExp(r'\s+')).first.toLowerCase();
    final cmd = word.isEmpty ? null : _find(word.replaceFirst('#', ''));
    if (cmd == null) {
      return const HashResult(
        HashKind.info,
        'Type # to see the commands, then pick one.',
      );
    }
    final usage = cmd.usage.isEmpty ? '#${cmd.name}' : cmd.usage;
    return HashResult(HashKind.info, '$usage: ${cmd.summary}');
  }

  /// The reason a raw line may not leave the phone, or null when it may. A
  /// message to a person or group goes out raw only when the policy says
  /// plain; encrypted, unknown, or a target that cannot be worked out is held.
  Future<String?> _blockedMessage(HashCommand cmd, String rest) async {
    final convId = _targetOf(cmd, rest);
    if (convId == null) return encryptedBlock;
    if (SeedUi.isActive) {
      return SeedUi.isEncrypted(convId) ? encryptedBlock : null;
    }
    return switch (await _messages.verdictOf(convId)) {
      EncryptionVerdict.plain => null,
      EncryptionVerdict.encrypted => encryptedBlock,
      EncryptionVerdict.unknown => _unknownBlock,
    };
  }

  /// The conversation a message-sending command names, or null when it cannot
  /// be told. `#reply` is the global room.
  String? _targetOf(HashCommand cmd, String rest) {
    switch (cmd.name) {
      case 'reply':
        return 'global';
      case 'replydm':
        final user = rest.split(RegExp(r'\s+')).first.toLowerCase();
        return user.isEmpty ? null : 'dm:$user';
      case 'groupmsg':
      case 'replygroup':
        final name = _groupIn(rest);
        return name == null ? null : 'group:$name';
    }
    return null;
  }

  /// The longest of my groups the line starts with (names may hold spaces).
  String? _groupIn(String rest) {
    final line = rest.toLowerCase();
    String? best;
    final groups = SeedUi.isActive
        ? SeedUi.conversations()
        : _conversations.conversations;
    for (final c in groups) {
      if (c.kind != 'group') continue;
      final name = c.convId.substring(6);
      final n = name.toLowerCase();
      final isMatch =
          line == n || line.startsWith('$n ') || line.startsWith('$n\t');
      if (isMatch && (best == null || name.length > best.length)) best = name;
    }
    return best;
  }

  Future<HashResult> _sendRaw(HashCommand cmd, String line) async {
    final isSd = cmd.isCustom || cmd.replies.contains('sd');
    if (isSd) {
      try {
        final data = await _socket.hashCall(line, cmd.name);
        return HashResult(HashKind.info, _summary(data));
      } on SocketCallError catch (e) {
        return HashResult(HashKind.error, _sdProblem(e));
      }
    }
    final types = {...cmd.replies};
    final reply = Completer<Map<String, dynamic>?>();
    final sub = _socket.events.listen((e) {
      final type = e['type'];
      final isMine =
          types.contains(type) || (type == 'error' && e['conv'] == null);
      if (isMine && !reply.isCompleted) reply.complete(e);
    });
    try {
      if (!await _socket.sendCommand(line)) {
        return const HashResult(HashKind.needsConnection, 'Needs a connection');
      }
      final event = await reply.future.timeout(
        _replyWait,
        onTimeout: () => null,
      );
      if (event == null) return const HashResult(HashKind.info, 'Sent');
      if (event['type'] == 'error') {
        return HashResult(HashKind.error, _errorText(event));
      }
      final text = _eventSummary(event);
      return text == null
          ? const HashResult(HashKind.done)
          : HashResult(HashKind.info, text);
    } finally {
      await sub.cancel();
    }
  }

  // ---- sending a direct message --------------------------------------------

  /// `#dm user text` and `@user text`: the normal direct-message send, whether
  /// or not the thread is encrypted. Never a raw line.
  Future<HashResult> sendDirect(String user, String text) async {
    final u = user.toLowerCase();
    final me = (_store.userId ?? SeedMessages.me).toLowerCase();
    if (u.isEmpty || u.length > 24 || u.contains(RegExp(r'\s'))) {
      return const HashResult(
        HashKind.invalid,
        'That is not a valid username.',
      );
    }
    if (u == me) {
      return const HashResult(HashKind.invalid, "You can't message yourself.");
    }
    if (text.length > _maxLength) {
      return const HashResult(
        HashKind.invalid,
        'Messages can be up to $_maxLength characters.',
      );
    }
    final convId = 'dm:$u';
    if (SeedUi.isActive) return _sendSeed(u, convId, text);
    final isKnown = _conversations.conversations.any((c) => c.convId == convId);
    if (!isKnown) {
      if (!_socket.isOnline) {
        return const HashResult(HashKind.needsConnection, 'Needs a connection');
      }
      final problem = await _checkUser(u);
      if (problem != null) return problem;
    }
    final result = await _messages.sendText(convId, text);
    return switch (result) {
      SendResult.queued => HashResult(
        HashKind.directQueued,
        '',
        u,
        convId,
        _messages.lastCid,
      ),
      SendResult.blocked => HashResult(HashKind.blocked, _messages.lastBlock),
      SendResult.tooLong => const HashResult(
        HashKind.invalid,
        'Messages can be up to $_maxLength characters.',
      ),
      _ => const HashResult(HashKind.error, "That message couldn't be sent."),
    };
  }

  HashResult _sendSeed(String user, String convId, String text) {
    final rows = SeedUi.conversations();
    final conv = rows.where((c) => c.convId == convId).firstOrNull;
    if (conv == null) {
      return HashResult(HashKind.error, "There's no @$user. Check the name.");
    }
    final gate = SeedUi.e2eGate(convId);
    if (gate != null) return HashResult(HashKind.blocked, gate.reason);
    final cid = SeedMessages.send(convId, text, isEncrypted: conv.isEncrypted);
    return HashResult(HashKind.directQueued, '', user, convId, cid);
  }

  /// A person I have no thread with: the server must know them, and the
  /// organisation's rules must let me message them.
  Future<HashResult?> _checkUser(String user) async {
    try {
      final data = await _socket.sdCall('users.search', {'q': user});
      final match = (data['users'] as List? ?? const [])
          .whereType<Map>()
          .where((u) => idText(u['username']).toLowerCase() == user)
          .firstOrNull;
      if (match == null) {
        return HashResult(
          HashKind.error,
          "There's no @$user. Check the name and try again.",
        );
      }
      if (match['canInteract'] == false) {
        return HashResult(
          HashKind.error,
          "This organisation's rules don't allow you to message @$user.",
        );
      }
      return null;
    } on SocketCallError catch (_) {
      return HashResult(
        HashKind.error,
        "Couldn't check @$user right now. Try again.",
      );
    }
  }

  /// Why a queued direct message failed, in plain words.
  static String failureText(String? reason, String user) {
    final r = reason ?? '';
    if (r == 'not_associated') {
      return "You're not connected with @$user yet. Connect with them first, then try again.";
    }
    if (r == MessageRepository.couldNotConfirm) {
      return "Couldn't confirm delivery to @$user. Open the chat to try again.";
    }
    return "Couldn't send to @$user. Open the chat to try again.";
  }

  // ---- reading the answers -------------------------------------------------

  static String _errorText(Map<String, dynamic> e) {
    final code = idText(e['code']);
    final text = idText(e['text']);
    if (code == 'unknown_command') return 'Unknown command';
    if (code == 'not_associated') {
      return "You're not connected with them yet. Connect first.";
    }
    if (text.contains('Too many commands')) {
      return 'Too many commands. Wait a moment and try again.';
    }
    return text.isEmpty ? "That didn't work." : text;
  }

  static String _sdProblem(SocketCallError e) => switch (e.code) {
    'forbidden' || 'admin_locked' => "You don't have permission to do that.",
    'unauthenticated' ||
    'session_expired' => 'Your session ended. Sign in again.',
    'rate_limited' || 'busy' => 'Too many commands. Wait a moment.',
    'timeout' || 'disconnected' || 'not_connected' => 'Needs a connection',
    _ => e.message.isEmpty ? "That didn't work." : e.message,
  };

  /// One line for the first list in an `sd` answer; "Done" when it has none.
  static String _summary(Map<String, dynamic> data) {
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is! List) continue;
      if (value.isEmpty) return 'Nothing to show';
      final names = [
        for (final item in value.take(3))
          if (_label(item).isNotEmpty) _label(item),
      ];
      final more = value.length > 3 ? ' and ${value.length - 3} more' : '';
      return names.isEmpty
          ? '${value.length} ${entry.key}'
          : '${value.length} ${entry.key}: ${names.join(', ')}$more';
    }
    return 'Done';
  }

  static String _label(Object? item) {
    if (item is! Map) return item == null ? '' : idText(item);
    for (final k in const ['name', 'caption', 'title', 'username', 'user']) {
      final v = idText(item[k]);
      if (v.isNotEmpty) return v;
    }
    return idText(item['text']);
  }

  /// A line for the chat commands whose answer is not already shown by the
  /// screens that read it (a message ack needs none).
  static String? _eventSummary(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'users':
        final list = [for (final u in (e['list'] as List? ?? [])) idText(u)];
        return list.isEmpty ? 'No one is online' : 'Online: ${list.join(', ')}';
      case 'groups':
        final list = [
          for (final g in (e['list'] as List? ?? []))
            if (g is Map) idText(g['name']),
        ];
        return list.isEmpty
            ? "You're not in any groups"
            : 'Groups: ${list.join(', ')}';
      case 'group_created':
        return 'Group "${idText(e['name'])}" now has ${(e['members'] as List? ?? []).length} members';
      case 'left_group':
        return 'Left "${idText(e['text'])}"';
      case 'profile':
        final status = idText(e['status']);
        return '${idText(e['user'] ?? e['name'])}: ${status.isEmpty ? 'no status' : status}';
      case 'conversations':
        return 'Inbox refreshed';
      case 'history':
        return 'History refreshed';
    }
    return null;
  }
}
