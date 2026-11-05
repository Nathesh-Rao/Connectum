import 'dart:async';

import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../features/chats/models/chat_person.dart';
import '../models/group_add.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';

/// Creating a group and adding people. `/creategroup` and `/addmember` take no
/// `cid`, so nothing here is queued or retried by itself: each command is sent
/// once, one at a time, and its reply decides the result.
class GroupRepository extends GetxService {
  GroupRepository(this._socket, this._session, this._conversations);

  final SocketService _socket;
  final SessionStore _session;
  final ConversationRepository _conversations;

  static const maxNameLength = 32;
  static const maxEncryptedMembers = 200;
  static const _gap = Duration(milliseconds: 400);
  static const _replyWait = Duration(seconds: 12);
  static const _pageSize = 30;

  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  /// The same clean-up the server does: no control characters, runs of
  /// whitespace become one space, trimmed, cut to 32.
  static String normalize(String raw) {
    final clean = raw
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.length > maxNameLength
        ? clean.substring(0, maxNameLength).trimRight()
        : clean;
  }

  /// Why [name] (already normalised) cannot be used, from the groups stored
  /// here; null when it looks free. Case-sensitive, like the server. The
  /// server also knows groups I am not in, so it can still refuse.
  static String? checkName(String name, Iterable<String> existing) {
    for (final other in existing) {
      if (other == name) return 'You already have a group with that name.';
      if (other.startsWith('$name ') || name.startsWith('$other ')) {
        return 'Too close to the group "$other": one name starts with the '
            'other.';
      }
    }
    return null;
  }

  // ---- people ----------------------------------------------------------------

  Future<GroupPeoplePage> colleagues({String query = '', String? after}) async {
    if (SeedUi.isActive) return SeedUi.groupPeople(query);
    final data = await _socket.sdCall('users.colleagues', {
      if (query.isNotEmpty) 'q': query,
      'after': ?after,
      'limit': _pageSize,
    });
    return GroupPeoplePage(
      [
        for (final u in (data['people'] as List? ?? []).whereType<Map>())
          if (idText(u['username']).isNotEmpty) _person(u),
      ],
      hasMore: data['hasMore'] == true,
      next: data['next'] == null ? null : idText(data['next']),
    );
  }

  /// People outside the colleagues list, for a typed query of 3 or more.
  Future<List<ChatPerson>> search(String query) async {
    if (SeedUi.isActive) return const [];
    final data = await _socket.sdCall('users.search', {'q': query});
    return [
      for (final u in (data['users'] as List? ?? []).whereType<Map>())
        if (idText(u['username']).isNotEmpty)
          ChatPerson(
            username: idText(u['username']),
            name: idText(u['name']).isNotEmpty
                ? idText(u['name'])
                : idText(u['username']),
            source: 'search',
            canInteract: u['canInteract'] is bool
                ? u['canInteract'] as bool
                : null,
          ),
    ];
  }

  static ChatPerson _person(Map u) {
    final detail = [
      idText(u['designation']),
      idText(u['department']),
    ].where((t) => t.isNotEmpty).join(' · ');
    return ChatPerson(
      username: idText(u['username']),
      name: idText(u['name']).isNotEmpty
          ? idText(u['name'])
          : idText(u['username']),
      source: u['connected'] == true ? 'connection' : 'colleague',
      detail: detail,
    );
  }

  // ---- commands --------------------------------------------------------------

  Future<GroupCreateResult> create(String name) async {
    if (SeedUi.isActive) return SeedUi.createGroup(name);
    if (!_socket.isOnline) {
      return const GroupCreateResult(GroupCreateStatus.offline);
    }
    final Map<String, dynamic>? reply;
    try {
      reply = await _command(
        '/creategroup $name',
        (e) => e['type'] == 'group_created' && idText(e['name']) == name,
      );
    } on SocketCallError catch (_) {
      return const GroupCreateResult(GroupCreateStatus.offline);
    }
    if (reply == null) {
      return const GroupCreateResult(GroupCreateStatus.unconfirmed);
    }
    if (reply['type'] == 'error') {
      return GroupCreateResult(GroupCreateStatus.refused, _errorText(reply));
    }
    await _conversations.saveGroup(reply);
    return const GroupCreateResult(GroupCreateStatus.created);
  }

  /// One `/addmember`. "Already in the group" counts as added, so a person
  /// whose first answer was lost can be tried again safely.
  Future<GroupAddResult> addMember(String group, ChatPerson person) async {
    if (SeedUi.isActive) return SeedUi.addMember(person);
    final user = person.username.toLowerCase();
    final Map<String, dynamic>? reply;
    try {
      reply = await _command(
        '/addmember $group ${person.username}',
        (e) =>
            (e['type'] == 'group_created' &&
                idText(e['name']) == group &&
                _has(e['members'], user)) ||
            (e['type'] == 'group_invite_pending' &&
                idText(e['group']) == group &&
                idText(e['user']).toLowerCase() == user),
      );
    } on SocketCallError catch (_) {
      return GroupAddResult(
        person,
        GroupAddStatus.failed,
        'Not sent: the connection was lost.',
      );
    }
    if (reply == null) {
      return GroupAddResult(
        person,
        GroupAddStatus.failed,
        'No answer from the server. Check the member list before trying again.',
      );
    }
    switch (reply['type']) {
      case 'error':
        final text = _errorText(reply);
        return GroupAddResult(
          person,
          text.contains('already in the group')
              ? GroupAddStatus.added
              : GroupAddStatus.failed,
          text,
        );
      case 'group_invite_pending':
        return GroupAddResult(person, GroupAddStatus.invited);
      default:
        await _conversations.saveGroup(reply);
        return GroupAddResult(person, GroupAddStatus.added);
    }
  }

  /// After a lost or late `/creategroup` reply: asks the server for my groups
  /// and says whether one with this name is mine. Null when that is not
  /// answered either.
  Future<bool?> isMyGroup(String name) async {
    if (SeedUi.isActive) return false;
    final Map<String, dynamic>? reply;
    try {
      reply = await _command('/groups', (e) => e['type'] == 'groups');
    } on SocketCallError catch (_) {
      return null;
    }
    if (reply == null || reply['type'] != 'groups') return null;
    final me = (_session.userId ?? '').toLowerCase();
    for (final g in (reply['list'] as List? ?? []).whereType<Map>()) {
      if (idText(g['name']) == name && idText(g['owner']).toLowerCase() == me) {
        await _conversations.saveGroup({...g.cast<String, dynamic>()});
        return true;
      }
    }
    return false;
  }

  /// Sends one line no sooner than [_gap] after the last one and waits for its
  /// reply: [isReply] or a plain `error`. Null when nothing came in time. There
  /// is no request id, so only one such command is ever in flight.
  Future<Map<String, dynamic>?> _command(
    String line,
    bool Function(Map<String, dynamic>) isReply,
  ) async {
    final wait = _gap - DateTime.now().difference(_lastSent);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    final reply = Completer<Map<String, dynamic>>();
    final sub = _socket.events.listen((e) {
      final isMine = isReply(e) || (e['type'] == 'error' && e['conv'] == null);
      if (isMine && !reply.isCompleted) reply.complete(e);
    });
    try {
      final isSent = await _socket.sendCommand(line);
      _lastSent = DateTime.now();
      if (!isSent) throw const SocketCallError('not_connected');
      return await reply.future.timeout(_replyWait);
    } on TimeoutException {
      return null;
    } finally {
      await sub.cancel();
    }
  }

  static bool _has(Object? members, String user) =>
      members is List && members.any((m) => idText(m).toLowerCase() == user);

  static String _errorText(Map<String, dynamic> e) {
    final text = idText(e['text']);
    return text.isEmpty ? 'The server refused this.' : text;
  }
}
