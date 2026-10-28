import 'dart:async';

import 'package:get/get.dart';

import '../models/ids.dart';
import '../socket/socket_service.dart';

enum PresenceDot { none, online, offline }

/// Who is online, from `/list`. The protocol has no presence event, only that
/// list plus "has joined / has left" notices, so the list is asked again on
/// those and every minute. Kept in memory: it is never written to SQLite.
/// A dot is shown only while the data is under two minutes old and the socket
/// is online, so a green dot never comes from stale data.
class PresenceRepository extends GetxService {
  PresenceRepository(this._socket);

  static const _freshFor = Duration(minutes: 2);
  static const _every = Duration(minutes: 1);

  final SocketService _socket;

  final online = <String>{}.obs;
  final isFresh = false.obs;
  Timer? _staleTimer;
  Timer? _repeat;
  Timer? _debounce;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    _socket.onOnline.listen((_) {
      refresh();
      _repeat?.cancel();
      _repeat = Timer.periodic(_every, (_) => refresh());
    });
    ever(_socket.connection, (state) {
      if (state == SocketState.online) return;
      _repeat?.cancel();
      _staleTimer?.cancel();
      isFresh.value = false;
    });
  }

  Future<void> refresh() async {
    if (_socket.isOnline) await _socket.sendCommand('/list');
  }

  /// Reads the Rx values it depends on, so call it inside an Obx.
  PresenceDot dotFor(String username) {
    final connection = _socket.connection.value;
    if (!isFresh.value || connection != SocketState.online) {
      return PresenceDot.none;
    }
    return online.contains(username.toLowerCase())
        ? PresenceDot.online
        : PresenceDot.offline;
  }

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'users':
        online.assignAll(
          ((e['list'] as List?) ?? []).map((u) => idText(u).toLowerCase()),
        );
        isFresh.value = true;
        _staleTimer?.cancel();
        _staleTimer = Timer(_freshFor, () => isFresh.value = false);
      case 'system':
        final text = idText(e['text']);
        if (text.contains(' has joined') ||
            text.contains(' has left') ||
            text.contains(' has disconnected')) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 1), refresh);
        }
    }
  }

  @override
  void onClose() {
    _staleTimer?.cancel();
    _repeat?.cancel();
    _debounce?.cancel();
    super.onClose();
  }
}
