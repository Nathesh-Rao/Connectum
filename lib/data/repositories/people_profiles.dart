import 'package:get/get.dart';

import 'package:connectum/core/log/log.dart';
import 'package:connectum/data/models/models.dart';
import 'package:connectum/data/socket/socket.dart';
import '../profile/presence.dart';
import '../session_store.dart';

/// What a `profile` event says about one person.
class PersonProfile {
  const PersonProfile({this.status, this.presence});

  /// The status message; null when none.
  final String? status;

  /// The presence the person chose; null when they never did.
  final Presence? presence;
}

/// People's status message and chosen presence, by lower-case username, from
/// the `profile` event (live, one per known person after `welcome`, and the
/// `/getprofile` answer). Kept in memory: the server sends them again on every
/// connect.
class PeopleProfiles extends GetxService {
  PeopleProfiles(this._socket, this._session);

  final SocketService _socket;
  final SessionStore _session;

  final profiles = <String, PersonProfile>{}.obs;
  String? _scope;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(
      (event) => fireAndLog('people_profiles', () async => onEvent(event)),
      onError: streamOnError('people_profiles'),
    );
    _scope = _scopeNow;
    ever(_session.current, (_) {
      if (_scope == _scopeNow) return;
      _scope = _scopeNow;
      profiles.clear();
    });
  }

  String? get _scopeNow => '${_session.orgId}/${_session.userId}';

  /// The status message of [username], or null. Reads an Rx value.
  String? statusOf(String? username) => _of(username)?.status;

  /// What [username] chose, or null. Reads an Rx value.
  Presence? chosenOf(String? username) => _of(username)?.presence;

  /// What [username] shows: the chosen presence, else the status text's
  /// reading. Display only. Reads an Rx value.
  Presence presenceOf(String? username) {
    final p = _of(username);
    return Presence.of(p?.presence, p?.status);
  }

  PersonProfile? _of(String? username) {
    if (username == null || username.isEmpty) return null;
    return profiles[username.toLowerCase()];
  }

  /// Takes one `profile` event.
  void onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'profile') return;
    final user = idText(e['user']).toLowerCase();
    if (user.isEmpty) return;
    final text = e['status'] == null ? '' : idText(e['status']);
    final status = text.trim().isEmpty ? null : text;
    final isMe = user == (_session.userId ?? '').toLowerCase();
    // Your own event without a `presence` key keeps what you have; a null one
    // (or any other person's event without it) says "never chosen".
    final keeps = isMe && !e.containsKey('presence');
    profiles[user] = PersonProfile(
      status: status,
      presence: keeps
          ? profiles[user]?.presence
          : Presence.parse(e['presence']),
    );
  }
}
