import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../db/app_database.dart';
import '../models/ids.dart';
import '../session_store.dart';
import '../socket/socket_service.dart';
import 'conversation_repository.dart';

/// People's picture addresses, by lower-case username. The server pushes a
/// `profile` event (`{user, avatar|null}`) when anyone changes their picture,
/// and one per known person after `welcome`; people lists carry `avatar` too.
/// Kept in SQLite per organisation and person, so pictures show offline.
/// Direct chats read their picture from the conversation row, which this keeps
/// current; everything else (the own picture, members, mentions) reads here.
class PeopleAvatars extends GetxService {
  PeopleAvatars(this._db, this._session, this._socket, this._conversations);

  final AppDatabase _db;
  final SessionStore _session;
  final SocketService _socket;
  final ConversationRepository _conversations;

  final urls = <String, String>{}.obs;
  String? _scope;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    _scope = _scopeNow;
    ever(_session.current, (_) {
      if (_scope == _scopeNow) return;
      _scope = _scopeNow;
      urls.clear();
      _load();
    });
    _load();
  }

  String? get _scopeNow => '${_session.orgId}/${_session.userId}';

  /// The picture address of [username], or null. Reads an Rx value: call it
  /// inside an Obx.
  String? urlOf(String? username) {
    if (username == null || username.isEmpty) return null;
    return urls[username.toLowerCase()];
  }

  /// The signed-in person's own picture. Reads an Rx value.
  String? get own => urlOf(_session.userId);

  Future<void> _load() async {
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    try {
      final rows = await _db.query(
        'SELECT username, avatar FROM people_avatars WHERE org_id = ? AND user_id = ?',
        [org, user],
      );
      if (org != _session.orgId || user != _session.userId) return;
      urls.addAll({
        for (final r in rows) idText(r['username']): idText(r['avatar']),
      });
    } catch (e) {
      debugPrint('people avatars: $e');
    }
  }

  /// Records [url] (null = none) as [username]'s picture: the screens change
  /// at once, then SQLite and the direct chat row follow.
  Future<void> set(String username, String? url) async {
    final who = username.toLowerCase();
    if (who.isEmpty) return;
    if (url == null || url.isEmpty) {
      urls.remove(who);
    } else {
      urls[who] = url;
    }
    final org = _session.orgId;
    final user = _session.userId;
    if (org == null || user == null) return;
    // A picture that is only on screen (the demo, or just cropped and not yet
    // sent) is not kept.
    final isKept = url == null || !url.startsWith('memory:');
    try {
      if (isKept) {
        if (url == null || url.isEmpty) {
          await _db.update(
            'DELETE FROM people_avatars WHERE org_id = ? AND user_id = ? AND username = ?',
            [org, user, who],
          );
        } else {
          await _db.update(
            'INSERT OR REPLACE INTO people_avatars(org_id, user_id, username, avatar) VALUES(?, ?, ?, ?)',
            [org, user, who, url],
          );
        }
      }
      if (isKept) await _conversations.setPeerAvatar(who, url);
    } catch (e) {
      debugPrint('people avatars: $e');
    }
  }

  /// Takes the pictures a people list carried (`avatar` per person row).
  Future<void> learn(Map<String, String?> byUsername) async {
    for (final e in byUsername.entries) {
      if (urlOf(e.key) == e.value ||
          (e.value == null && urlOf(e.key) == null)) {
        continue;
      }
      await set(e.key, e.value);
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!_socket.isCurrent(e) || e['type'] != 'profile') return;
    final user = idText(e['user']);
    if (user.isEmpty) return;
    final avatar = e['avatar'];
    set(user, avatar == null || idText(avatar).isEmpty ? null : idText(avatar));
  }
}
