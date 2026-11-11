import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../core/debug/seed_messages.dart';
import '../../core/debug/seed_ui.dart';
import '../commands/command_handlers.dart';
import '../commands/command_line.dart';
import '../commands/command_menu.dart';
import '../commands/command_reply.dart';
import '../models/hash_command.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/connectivity_service.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';
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
  usage,
  draft,
  screen,
  rows,
  confirm,
  soon,
  success,
  notice,
}

/// One line of a list a command opened (people, groups, associates).
class CommandRow {
  const CommandRow(this.title, {this.subtitle = '', this.convId = ''});

  final String title;
  final String subtitle;

  /// The conversation a tap opens; empty when there is none.
  final String convId;
}

/// What a `#` line or an `@user` line did, for the screen to show.
class HashResult {
  const HashResult(
    this.kind, [
    this.text = '',
    this.user = '',
    this.convId = '',
    this.cid = '',
    this.suggestions = const [],
    this.rows = const [],
    this.target = '',
  ]);

  final HashKind kind;
  final String text;
  final String user;
  final String convId;
  final String cid;

  /// Command names the server suggests for an unknown one.
  final List<String> suggestions;
  final List<CommandRow> rows;

  /// `screen`: what to open. `confirm`: the group.
  final String target;

  /// Nothing more to fix: the screen clears the composer. Everything else
  /// keeps the typed text so it can be corrected or sent again.
  bool get isFinished =>
      kind == HashKind.directQueued ||
      kind == HashKind.info ||
      kind == HashKind.done ||
      kind == HashKind.draft ||
      kind == HashKind.screen ||
      kind == HashKind.rows ||
      kind == HashKind.success ||
      kind == HashKind.soon ||
      kind == HashKind.notice;
}

/// The `#` command catalogue and the one place a `#` line or an `@user` line is
/// turned into an action.
///
/// A `#` line is never a chat message. `#dm` and `#groupmsg` are not sent at
/// all: they open the chat with the text as a draft, so the text goes out of
/// the normal composer (which encrypts where the chat is encrypted); the
/// server would run a raw line in the clear.
class CommandRepository extends GetxService {
  CommandRepository(
    this._socket,
    this._store,
    this._connectivity,
    this._messages,
    this._conversations, {
    Duration replyWait = const Duration(seconds: 12),
  }) : _replyWait = replyWait;

  static const _maxLength = 2000;
  static const escapeNotice =
      'Messages starting with ## go to the general room, which is not available in the app.';
  static const comingSoon = 'This command is coming soon in the app.';
  static const noPerson = 'No such person.';
  static const noGroup = 'No such group.';

  /// Frames each command answers with when the catalogue does not say.
  static const _expected = {
    'users': ['users'],
    'groups': ['groups'],
    'creategroup': ['group_created'],
    'addmember': ['group_created', 'group_invite_pending'],
    'leavegroup': ['left_group'],
  };

  final SocketService _socket;
  final SessionStore _store;
  final ConnectivityService _connectivity;
  final MessageRepository _messages;
  final ConversationRepository _conversations;
  final Duration _replyWait;

  final catalog = <HashCommand>[].obs;
  final categories = <CommandCategory>[].obs;
  final isLoading = false.obs;

  /// What the person may do, from `perm.mine`; null until known. Commands that
  /// need a permission stay out of the menu while it is null.
  final permissions = Rxn<Set<String>>();
  final isAdmin = false.obs;

  String? _loadedOrg;
  bool _isFresh = false;
  Future<void>? _loading;
  final _cids = <String, String>{};

  static bool isHashLine(String text) => CommandLine.isCommand(text);

  bool get isOnline => SeedUi.isActive
      ? _connectivity.state.value != AppConnectivity.offline
      : _socket.isOnline;

  @override
  void onInit() {
    super.onInit();
    _socket.listenOnline('commands', () {
      _isFresh = false;
      if (_store.orgId != null) return ensureLoaded();
    });
    _socket.events.listen((e) {
      if (e['type'] == 'sd_event' && e['event'] == 'permissions_changed') {
        _isFresh = false;
        unawaited(ensureLoaded());
      }
    });
    ever(_store.current, (_) {
      _isFresh = false;
      _loadedOrg = null;
      catalog.clear();
      categories.clear();
      permissions.value = null;
      isAdmin.value = false;
      _cids.clear();
    });
  }

  // ---- the catalog ---------------------------------------------------------

  /// The rows the menu shows for the text after `#`.
  List<HashCommand> menu(String query) => CommandMenu.filter(
    catalog,
    query,
    categories: categories,
    permissions: permissions.value,
    isAdmin: isAdmin.value,
  );

  HashCommand? find(String word) => CommandMenu.find(catalog, word);

  /// Reads the cache for this organisation, then asks the server once per
  /// connection (`/cmds`, `perm.mine` and `cmd.list`) when online.
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

  String _key(String org) => 'cmds.catalog2.$org';

  Future<void> _readCache(String org) async {
    try {
      final raw = await _store.readValue(_key(org));
      if (raw == null) return;
      final data = (jsonDecode(raw) as Map).cast<String, dynamic>();
      final all = [
        for (final j in (data['commands'] as List))
          HashCommand.fromJson(
            (j as Map).cast<String, dynamic>(),
            isCustom: j['custom'] == true,
          ),
      ];
      categories.assignAll(_categoriesOf(data['categories']));
      catalog.assignAll([...all, ...CommandMenu.localEntries(all)]);
    } catch (_) {}
  }

  static List<CommandCategory> _categoriesOf(Object? list) => [
    for (final c in (list as List? ?? const []))
      if (c is Map) CommandCategory(idText(c['id']), idText(c['label'])),
  ];

  Future<void> _fetch(String org) async {
    final wait = _next((e) => e['type'] == 'cmd_catalog');
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
    final all = [...builtIn, ...custom];
    categories.assignAll([
      ..._categoriesOf(event['categories']),
      if (custom.isNotEmpty) const CommandCategory('custom', 'Custom'),
    ]);
    catalog.assignAll([...all, ...CommandMenu.localEntries(all)]);
    _isFresh = true;
    await _store.writeValue(
      _key(org),
      jsonEncode({
        'categories': [
          for (final c in categories) {'id': c.id, 'label': c.label},
        ],
        'commands': [for (final c in all) c.toJson()],
      }),
    );
    await _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    try {
      final data = await _socket.sdCall('perm.mine', {});
      permissions.value = {
        for (final p in (data['permissions'] as List? ?? const [])) idText(p),
      };
      isAdmin.value = data['isAdmin'] == true;
    } on SocketCallError catch (_) {}
  }

  Future<Map<String, dynamic>?> _next(
    bool Function(Map<String, dynamic>) isMine, [
    Duration timeout = const Duration(seconds: 8),
  ]) {
    final done = Completer<Map<String, dynamic>?>();
    final sub = _socket.events.listen((e) {
      if (isMine(e) && !done.isCompleted) done.complete(e);
    });
    return done.future
        .timeout(timeout, onTimeout: () => null)
        .whenComplete(sub.cancel);
  }

  /// `#help <name>`: one command in full; the catalogue entry when the server
  /// does not answer.
  Future<HashCommand?> detail(String name) async {
    final local = find(name);
    if (!isOnline || SeedUi.isActive) return local;
    final wait = _next((e) => e['type'] == 'cmd_help');
    if (!await _socket.sendCommand('#help $name')) return local;
    final event = await wait;
    final raw = event?['command'] ?? (event?['commands'] as List?)?.firstOrNull;
    if (raw is! Map) return local;
    final c = HashCommand.fromJson(raw.cast<String, dynamic>());
    return c.name.isEmpty ? local : c;
  }

  // ---- suggestions -----------------------------------------------------------

  /// A suggester wired to `/cmdcomplete`; the caller owns it and disposes it.
  CommandSuggester createSuggester() => CommandSuggester(_complete);

  Future<CommandSuggestions?> _complete(
    String input,
    int page,
    int reqId,
  ) async {
    if (!isOnline || SeedUi.isActive) return null;
    final wait = _next(
      (e) => e['type'] == 'cmd_suggestions' && intOf(e['reqId']) == reqId,
      const Duration(seconds: 5),
    );
    final body = jsonEncode({
      'input': input,
      'page': page,
      'pageSize': CommandSuggester.pageSize,
      'reqId': reqId,
    });
    if (!await _socket.sendCommand('/cmdcomplete $body')) return null;
    final e = await wait;
    return e == null ? null : CommandSuggestions.fromFrame(e);
  }

  // ---- running a line ------------------------------------------------------

  /// Runs a line that starts with `#` and a letter. Online only, never queued.
  /// [activeConvId] is the open chat, for `#leavegroup` without a name.
  /// [isConfirmed] is set after the person agreed to a risky command.
  Future<HashResult> run(
    String line, {
    String? activeConvId,
    bool isConfirmed = false,
  }) async {
    if (CommandLine.isEscape(line)) {
      return const HashResult(HashKind.notice, escapeNotice);
    }
    final parsed = CommandLine.parse(line);
    if (parsed == null) {
      return const HashResult(HashKind.invalid, 'Not a command.');
    }
    await ensureLoaded();
    final cmd = find(parsed.name);
    if (cmd == null && catalog.isEmpty && !isOnline) {
      return const HashResult(HashKind.needsConnection, 'Needs a connection');
    }
    if (cmd == null) return _sendUnknown(parsed);
    if (!cmd.isAvailable || _isDenied(cmd)) {
      return HashResult(
        HashKind.blocked,
        "You don't have access to #${cmd.name}. Ask your administrator to give you the permission.",
      );
    }
    final handler = CommandHandlers.of(cmd);
    switch (handler.mode) {
      case CommandMode.soon:
        return const HashResult(HashKind.soon, comingSoon);
      case CommandMode.screen:
        return _screen(handler.target, parsed);
      case CommandMode.draft:
        return _draft(cmd, parsed, handler.target);
      case CommandMode.line:
      case CommandMode.list:
        break;
    }
    if (!isOnline) {
      return const HashResult(HashKind.needsConnection, 'Needs a connection');
    }
    final names = _groupNames();
    var args = parsed.bind(cmd, groupNames: names);
    if (cmd.name == 'leavegroup' && args['group'] == null) {
      final active = activeConvId ?? '';
      if (active.startsWith('group:')) {
        args = CommandArgs({'group': active.substring(6)}, '');
      }
    }
    final problem = CommandValidator.check(cmd, args);
    if (problem != null) return _usage(cmd, problem);
    if (cmd.name == 'addmember') {
      final denied = _notOwner(args['group'] ?? '');
      if (denied != null) return HashResult(HashKind.blocked, denied);
    }
    if (handler.isRisky && !isConfirmed) {
      return HashResult(
        HashKind.confirm,
        '',
        '',
        '',
        '',
        const [],
        const [],
        args['group'] ?? '',
      );
    }
    final text = _lineOf(cmd, parsed, args);
    if (SeedUi.isActive) return HashResult(HashKind.info, SeedUi.hashInfo(cmd));
    if (cmd.isLocal) return _localList();
    return _exchange(cmd, text, args);
  }

  bool _isDenied(HashCommand cmd) {
    final need = CommandMenu.permissionOf(cmd);
    final held = permissions.value;
    return need != null && held != null && !held.contains(need);
  }

  HashResult _usage(HashCommand cmd, String problem) => HashResult(
    HashKind.usage,
    cmd.usage.isEmpty ? problem : '$problem Usage: ${cmd.usage}',
  );

  Iterable<String> _groupNames() {
    final list = SeedUi.isActive
        ? SeedUi.conversations()
        : _conversations.conversations;
    return [
      for (final c in list)
        if (c.kind == 'group') c.convId.substring(6),
    ];
  }

  /// The web's check: only the owner adds people, when the owner is known.
  String? _notOwner(String group) {
    final me = (_store.userId ?? '').toLowerCase();
    for (final c in _conversations.conversations) {
      if (c.convId.toLowerCase() != 'group:${group.toLowerCase()}') continue;
      if (c.owner.isNotEmpty && c.owner.toLowerCase() != me) {
        return 'Only the group admin (${c.owner}) can add members';
      }
    }
    return null;
  }

  /// The line the socket gets: as typed (the server reads aliases itself),
  /// with the open group filled in for a bare `#leavegroup`.
  String _lineOf(HashCommand cmd, CommandLine parsed, CommandArgs args) {
    final rest = cmd.name == 'leavegroup' && parsed.rest.trim().isEmpty
        ? args['group'] ?? ''
        : parsed.rest;
    return '#${parsed.name}${rest.isEmpty ? '' : ' $rest'}';
  }

  HashResult _screen(String target, CommandLine parsed) {
    if (target == 'help') {
      return HashResult(
        HashKind.screen,
        '',
        '',
        '',
        '',
        const [],
        const [],
        parsed.rest.trim().isEmpty ? 'help' : 'help:${parsed.rest.trim()}',
      );
    }
    return HashResult(
      HashKind.screen,
      '',
      '',
      '',
      '',
      const [],
      const [],
      target,
    );
  }

  // ---- dm and groupmsg: a draft, never sent ----------------------------------

  Future<HashResult> _draft(
    HashCommand cmd,
    CommandLine parsed,
    String target,
  ) async {
    final isGroup = target == 'group';
    final args = parsed.bind(cmd, groupNames: _groupNames());
    final first = args[isGroup ? 'group' : 'user'] ?? '';
    if (first.isEmpty) {
      return _usage(cmd, 'Missing ${isGroup ? 'group' : 'user'}.');
    }
    final draft = args['text'] ?? '';
    if (draft.runes.length > _maxLength) {
      return _usage(cmd, 'text is too long (max $_maxLength characters).');
    }
    if (isGroup) {
      final name = _groupNames()
          .where((n) => n.toLowerCase() == first.toLowerCase())
          .firstOrNull;
      if (name == null) return const HashResult(HashKind.error, noGroup);
      return HashResult(HashKind.draft, draft, '', 'group:$name');
    }
    final user = first.toLowerCase();
    if (user == (_store.userId ?? '').toLowerCase()) {
      return const HashResult(HashKind.invalid, "You can't message yourself.");
    }
    final convId = 'dm:$user';
    if (!_knowsPerson(convId, user)) {
      if (!isOnline) {
        return const HashResult(HashKind.needsConnection, 'Needs a connection');
      }
      if (!await _isRealPerson(user)) {
        return const HashResult(HashKind.error, noPerson);
      }
    }
    return HashResult(HashKind.draft, draft, user, convId);
  }

  bool _knowsPerson(String convId, String user) {
    final list = SeedUi.isActive
        ? SeedUi.conversations()
        : _conversations.conversations;
    return list.any(
      (c) =>
          c.convId == convId ||
          (c.kind == 'group' && c.members.any((m) => m.toLowerCase() == user)),
    );
  }

  Future<bool> _isRealPerson(String user) async {
    try {
      final data = await _socket.sdCall('users.search', {'q': user});
      return (data['users'] as List? ?? const []).whereType<Map>().any(
        (u) => idText(u['username']).toLowerCase() == user,
      );
    } on SocketCallError catch (_) {
      return false;
    }
  }

  // ---- sending the line --------------------------------------------------------

  Future<HashResult> _sendUnknown(CommandLine parsed) async {
    if (!isOnline) {
      return const HashResult(HashKind.needsConnection, 'Needs a connection');
    }
    final text =
        '#${parsed.name}${parsed.rest.isEmpty ? '' : ' ${parsed.rest}'}';
    final reply = await _send(text, name: parsed.name, replies: const []);
    if (reply == null) return const HashResult(HashKind.error, noAnswer);
    return reply.isOk ? const HashResult(HashKind.done) : _failure(reply, null);
  }

  static const noAnswer = 'No answer from the server. Try again.';

  /// Sends [text] (with a `/c <cid>` wrapper where the server takes one) and
  /// waits for the frame that answers it. A retry of the same line reuses the
  /// client id, so the server never does it twice.
  Future<CommandReply?> _send(
    String text, {
    required String name,
    required List<String> replies,
    bool isSd = false,
    bool withCid = false,
  }) async {
    var line = text;
    if (withCid) line = '/c ${_cids.putIfAbsent(text, newCid)} $text';
    final reply = Completer<CommandReply>();
    final sub = _socket.events.listen((e) {
      final r = CommandReply.fromFrame(e, name: name, replies: replies);
      if (r != null && !reply.isCompleted) reply.complete(r);
    });
    try {
      if (isSd) {
        final call = _socket
            .hashCall(line, name)
            .then(
              (data) => CommandReply(frame: data),
              onError: (Object e) => e is SocketCallError
                  ? CommandReply(isOk: false, code: e.code, text: _sdProblem(e))
                  : CommandReply(isOk: false, text: "That didn't work."),
            );
        return await Future.any([call, reply.future]).timeout(_replyWait);
      }
      if (!await _socket.sendCommand(line)) {
        return const CommandReply(
          isOk: false,
          code: 'not_connected',
          text: 'Needs a connection',
        );
      }
      return await reply.future.timeout(_replyWait);
    } on TimeoutException {
      return null;
    } finally {
      await sub.cancel();
    }
  }

  Future<HashResult> _exchange(
    HashCommand cmd,
    String text,
    CommandArgs args,
  ) async {
    final handler = CommandHandlers.of(cmd);
    final isSd =
        cmd.isCustom ||
        cmd.replies.contains('sd') ||
        handler.target == 'associates';
    final replies = [...cmd.replies, ...?_expected[cmd.name]];
    final withCid =
        !cmd.isCustom && CommandHandlers.idempotent.contains(cmd.name);
    final reply = await _send(
      text,
      name: cmd.name,
      replies: replies,
      isSd: isSd,
      withCid: withCid,
    );
    if (reply == null) {
      return HashResult(
        HashKind.error,
        withCid
            ? 'No answer yet. Send it again; it will not be done twice.'
            : noAnswer,
      );
    }
    if (!reply.isOk) {
      return _failure(reply, cmd);
    }
    _cids.remove(text);
    return _success(cmd, handler, reply, args);
  }

  HashResult _failure(CommandReply reply, HashCommand? cmd) {
    switch (reply.code) {
      case 'unknown_command':
        return HashResult(
          HashKind.unknown,
          reply.message,
          '',
          '',
          '',
          reply.suggestions,
        );
      case 'usage':
        return HashResult(HashKind.usage, reply.message);
      case 'not_connected':
        return const HashResult(HashKind.needsConnection, 'Needs a connection');
    }
    return HashResult(HashKind.error, reply.message);
  }

  Future<HashResult> _success(
    HashCommand cmd,
    CommandHandler handler,
    CommandReply reply,
    CommandArgs args,
  ) async {
    final f = reply.frame;
    switch (cmd.name) {
      case 'creategroup':
        await _conversations.saveGroup(f);
        return const HashResult(HashKind.success, 'Group created');
      case 'addmember':
        final user = args['user'] ?? '';
        if (f['type'] == 'group_invite_pending') {
          return HashResult(HashKind.success, 'Invitation sent to $user');
        }
        await _conversations.saveGroup(f);
        return HashResult(HashKind.success, 'Added $user');
      case 'leavegroup':
        return HashResult(
          HashKind.success,
          'You left ${idText(f['text']).isEmpty ? args['group'] : idText(f['text'])}',
        );
    }
    switch (handler.target) {
      case 'users':
        final me = (_store.userId ?? '').toLowerCase();
        final rows = <CommandRow>[
          for (final u in (f['list'] as List? ?? const []))
            if (_userOf(u).isNotEmpty && _userOf(u).toLowerCase() != me)
              CommandRow(
                _userOf(u),
                subtitle: 'Online',
                convId: 'dm:${_userOf(u).toLowerCase()}',
              ),
        ];
        return HashResult(
          HashKind.rows,
          'Online now',
          '',
          '',
          '',
          const [],
          rows,
        );
      case 'groups':
        final rows = <CommandRow>[
          for (final g in (f['list'] as List? ?? const []).whereType<Map>())
            if (idText(g['name']).isNotEmpty)
              CommandRow(
                idText(g['name']),
                subtitle: _members((g['members'] as List?)?.length),
                convId: 'group:${idText(g['name'])}',
              ),
        ];
        return HashResult(
          HashKind.rows,
          'My groups',
          '',
          '',
          '',
          const [],
          rows,
        );
      case 'associates':
        return HashResult(
          HashKind.rows,
          'Connections',
          '',
          '',
          '',
          const [],
          _associates(f),
        );
      case 'custom':
        return HashResult(HashKind.info, _summary(f));
    }
    return const HashResult(HashKind.done);
  }

  static String _userOf(Object? u) =>
      u is Map ? idText(u['user'] ?? u['username'] ?? u['name']) : idText(u);

  static String _members(int? n) =>
      n == null ? '' : '$n member${n == 1 ? '' : 's'}';

  static List<CommandRow> _associates(Map<String, dynamic> f) => [
    for (final a in (f['associates'] as List? ?? const []).whereType<Map>())
      if (idText(a['user']).isNotEmpty)
        CommandRow(
          idText(a['user']),
          subtitle: [
            if (idText(a['relation']).isNotEmpty) idText(a['relation']),
            if (a['online'] == true) 'Online',
          ].join(' · '),
          convId: 'dm:${idText(a['user']).toLowerCase()}',
        ),
  ];

  /// The local `#connections` entry: the associates, asked for directly.
  Future<HashResult> _localList() async {
    try {
      final data = await _socket.sdCall('assoc.list', {});
      return HashResult(
        HashKind.rows,
        'Connections',
        '',
        '',
        '',
        const [],
        _associates(data),
      );
    } on SocketCallError catch (e) {
      return HashResult(HashKind.error, _sdProblem(e));
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
}
