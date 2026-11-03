import 'dart:async';

import 'package:get/get.dart';

import '../models/ids.dart';
import '../socket/socket_service.dart';

/// Who is typing, per conversation, from `typing_dm`, `group_typing` and
/// `typing` (the global room). A name disappears five seconds after its last
/// event, or as soon as that person's message arrives. In memory only.
class TypingRepository extends GetxService {
  TypingRepository(this._socket);

  static const _expiry = Duration(seconds: 5);

  final SocketService _socket;

  final _names = <String, RxList<String>>{};
  final _timers = <String, Timer>{};

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    ever(_socket.connection, (state) {
      if (state != SocketState.online) _clearAll();
    });
  }

  /// The people typing in [convId] right now. Reads an Rx list: use in an Obx.
  RxList<String> typingIn(String convId) =>
      _names.putIfAbsent(convId, () => <String>[].obs);

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'typing_dm':
        final from = idText(e['from']).toLowerCase();
        _note('dm:$from', from);
      case 'group_typing':
        _note('group:${idText(e['group'])}', idText(e['from']));
      case 'typing':
        _note('global', idText(e['text']));
      case 'private':
        _stop('dm:${idText(e['from']).toLowerCase()}', idText(e['from']));
      case 'group_message':
        _stop('group:${idText(e['group'])}', idText(e['from']));
      case 'chat':
        _stop('global', idText(e['from']));
    }
  }

  void _note(String convId, String name) {
    if (name.isEmpty) return;
    final list = typingIn(convId);
    if (!list.contains(name)) list.add(name);
    final key = '$convId|$name';
    _timers[key]?.cancel();
    _timers[key] = Timer(_expiry, () => _stop(convId, name));
  }

  void _stop(String convId, String name) {
    final key = '$convId|$name';
    _timers.remove(key)?.cancel();
    _names[convId]?.remove(name);
    _names[convId]?.remove(name.toLowerCase());
  }

  void _clearAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final list in _names.values) {
      list.clear();
    }
  }

  /// Debug and sample data: shows [name] as typing in [convId].
  void simulate(String convId, String name) => _note(convId, name);

  @override
  void onClose() {
    _clearAll();
    super.onClose();
  }
}
