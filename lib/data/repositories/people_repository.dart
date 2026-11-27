import 'package:get/get.dart';

import '../../core/debug/seed_ui.dart';
import '../../features/chats/models/chat_person.dart';
import '../../features/chats/models/person_link.dart';
import '../models/approval.dart';
import '../models/group_add.dart';
import '../models/ids.dart';
import '../socket/read_gate.dart';
import '../socket/socket_service.dart';

/// What to do with the optimistic "Requested" state when an invite fails.
enum InviteFix {
  /// The request was not made: back to Connect.
  rollBack,

  /// The server already has a pending request: stay on Requested.
  isRequested,

  /// They are already connected: move to Connected.
  isConnected,
}

/// A refused `assoc.invite`, in plain words. `{name}` is the person.
class InviteError {
  const InviteError(this.message, this.fix);

  final String message;
  final InviteFix fix;
}

/// The change one `request_created` / `request_resolved` event of an
/// `associate` request makes to a row.
class LinkChange {
  const LinkChange(this.username, this.link);

  /// The other person, lower case.
  final String username;
  final PersonLink link;
}

/// People for New chat: the paged list (`users.colleagues`), the exact search
/// (`users.search`), my connections (`assoc.list`) and my pending connection
/// requests (`req.list`) go through the shared [ReadGate]. `assoc.invite` is
/// a write and is sent once, never replayed.
class PeopleRepository extends GetxService {
  PeopleRepository(this._socket, this._gate);

  final SocketService _socket;
  final ReadGate _gate;

  /// The server allows 1 to 50 a page.
  static const pageSize = 30;

  /// `req.list` pages of 200, so at most this many pending requests are read.
  static const maxRequestPages = 5;

  /// One page of `users.colleagues`, asked the way the web does
  /// (`usePeopleList`): `q` always present (empty for the default listing),
  /// `limit` 30, `after` = the last `next`. A reply without a `people` list
  /// is an error ([SocketCallError] `bad_response`), never an empty page.
  Future<GroupPeoplePage> colleagues({String query = '', String? after}) async {
    if (SeedUi.isActive) return SeedUi.groupPeople(query);
    final data = await _gate.run(
      () => _socket.sdCall('users.colleagues', {
        'q': query,
        'limit': pageSize,
        'after': ?after,
      }),
    );
    return parseColleagues(data);
  }

  /// The `users.colleagues` answer. `connected` is the link flag; a row
  /// without a username is skipped; a missing `people` list throws.
  static GroupPeoplePage parseColleagues(Map<String, dynamic> data) {
    final raw = data['people'];
    if (raw is! List) throw const SocketCallError('bad_response');
    final next = data['next'];
    return GroupPeoplePage(
      [
        for (final u in raw.whereType<Map>())
          if (idText(u['username']).isNotEmpty)
            _person(u, u['connected'] == true ? 'connection' : 'colleague'),
      ],
      hasMore: data['hasMore'] == true,
      next: next is String && next.isNotEmpty ? next : null,
    );
  }

  /// The server's reason for a failed people read, in plain words.
  static String explainRead(Object error) {
    final code = error is SocketCallError ? error.code : '';
    switch (code) {
      case 'timeout' || 'disconnected' || 'not_connected':
        return "Couldn't reach the server. Check your connection.";
      case 'rate_limited' || 'busy':
        return 'The server is busy. Wait a moment and try again.';
      case 'forbidden':
        return "This organisation's rules don't let you see this list.";
      case 'password_change_required':
        return 'Change your password to continue.';
      case 'bad_response' || 'bad_json':
        return 'The server sent a list the app could not read.';
      case 'internal':
        return 'Something went wrong on the server. Try again.';
    }
    return "Couldn't load people. Try again.";
  }

  /// People outside the paged list, found by an exact username, e-mail or
  /// mobile number. A hit says whether it is already connected.
  Future<List<ChatPerson>> search(String query) async {
    if (SeedUi.isActive) return const [];
    final data = await _gate.run(
      () => _socket.sdCall('users.search', {'q': query}),
    );
    return [
      for (final u in (data['users'] as List? ?? []).whereType<Map>())
        if (idText(u['username']).isNotEmpty)
          _person(
            u,
            u['connected'] == true ? 'connection' : 'search',
            canInteract: u['canInteract'] is bool
                ? u['canInteract'] as bool
                : null,
          ),
    ];
  }

  /// My connections (`assoc.list`).
  Future<List<ChatPerson>> connections() async {
    if (SeedUi.isActive) return const [];
    final data = await _gate.run(() => _socket.sdCall('assoc.list', {}));
    return [
      for (final a in (data['associates'] as List? ?? []).whereType<Map>())
        if (a['user'] is Map &&
            idText((a['user'] as Map)['username']).isNotEmpty)
          _person(a['user'] as Map, 'connection'),
    ];
  }

  /// The pending `associate` requests joined by the other person (lower
  /// case): [PersonLink.requested] when I sent it, [PersonLink.asked] when
  /// they did. Pages of 200 (`req.list`, newest first).
  Future<Map<String, PersonLink>> pendingLinks(String me) async {
    if (SeedUi.isActive) return {};
    final links = <String, PersonLink>{};
    var offset = 0;
    for (var page = 0; page < maxRequestPages; page++) {
      final data = await _gate.run(
        () => _socket.sdCall('req.list', {
          'status': 'pending',
          'limit': 200,
          if (offset > 0) 'offset': offset,
        }),
      );
      final raw = data['requests'];
      final list = [
        if (raw is List)
          for (final j in raw) ?Approval.tryParse(j, viewer: me),
      ];
      for (final r in list) {
        final change = _change(r, me, isCreated: true);
        if (change != null) links[change.username] = change.link;
      }
      if (data['hasMore'] != true || list.isEmpty) break;
      offset += list.length;
    }
    return links;
  }

  /// `assoc.invite {to}`: asks [username] to connect. Throws
  /// [SocketCallError]; see [explain].
  Future<void> invite(String username) async {
    if (SeedUi.isActive) return;
    await _socket.sdCall('assoc.invite', {'to': username});
  }

  /// The words and the fix for a refused `assoc.invite`. The codes are the
  /// server's (`sd_reqs:create_associate` and the command rate limit):
  /// `invalid`, `not_found`, `already_associated`, `forbidden`, `duplicate`,
  /// `rate_limited`.
  static InviteError explain(SocketCallError e) {
    switch (e.code) {
      case 'invalid':
        return const InviteError(
          "You can't connect with yourself.",
          InviteFix.rollBack,
        );
      case 'not_found':
        return const InviteError(
          "{name} couldn't be found. They may have left the organisation.",
          InviteFix.rollBack,
        );
      case 'already_associated':
        return const InviteError(
          "You're already connected with {name}.",
          InviteFix.isConnected,
        );
      case 'forbidden':
        return const InviteError(
          "This organisation's rules don't allow you to connect with {name}.",
          InviteFix.rollBack,
        );
      case 'duplicate':
        return const InviteError(
          'A request to {name} is already waiting for their answer.',
          InviteFix.isRequested,
        );
      case 'rate_limited':
        return const InviteError(
          'Too many requests just now. Wait a few seconds and try again.',
          InviteFix.rollBack,
        );
    }
    if (e.isConnectionGap) {
      return const InviteError(
        "The request didn't reach {name}. Check your connection and try again.",
        InviteFix.rollBack,
      );
    }
    return const InviteError(
      "Couldn't send the request to {name}. Try again.",
      InviteFix.rollBack,
    );
  }

  /// The row change an `sd_event` makes, or null when it is not about a
  /// connection request. `request_created` reaches the person asked;
  /// `request_resolved` reaches both.
  static LinkChange? linkChange(Map<String, dynamic> event, String me) {
    if (event['type'] != 'sd_event') return null;
    final name = event['event'];
    if (name != 'request_created' && name != 'request_resolved') return null;
    final r = Approval.tryParse(event['data'], viewer: me);
    if (r == null) return null;
    return _change(r, me, isCreated: name == 'request_created');
  }

  static LinkChange? _change(Approval r, String me, {required bool isCreated}) {
    if (r.type != 'associate') return null;
    final mine = me.toLowerCase();
    final from = r.from.toLowerCase();
    final subject = r.subject.toLowerCase();
    final sentByMe = from == mine;
    final other = sentByMe ? subject : from;
    if (other.isEmpty || other == mine) return null;
    if (isCreated) {
      if (r.status != Approval.pending) return null;
      return LinkChange(
        other,
        sentByMe ? PersonLink.requested : PersonLink.asked,
      );
    }
    return switch (r.status) {
      Approval.accepted => LinkChange(other, PersonLink.connected),
      Approval.rejected ||
      Approval.ignored => LinkChange(other, PersonLink.none),
      _ => null,
    };
  }

  static String? _avatar(Map u) {
    final a = idText(u['avatar']);
    return a.isEmpty ? null : a;
  }

  static ChatPerson _person(Map u, String source, {bool? canInteract}) {
    final detail = [
      idText(u['designation']),
      idText(u['department']),
    ].where((t) => t.isNotEmpty).join(' · ');
    return ChatPerson(
      username: idText(u['username']),
      name: idText(u['name']).isNotEmpty
          ? idText(u['name'])
          : idText(u['username']),
      source: source,
      canInteract: canInteract,
      detail: detail,
      avatar: _avatar(u),
    );
  }
}
