import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../models/ids.dart';
import '../socket/socket_service.dart';

enum PresenceDot { none, online, offline }

/// Who is online. `/list` answers once at start, on resume and after every
/// reconnect; the live `presence` event keeps it current from then on. A
/// reconnect that takes over a live connection sends no event, so everything
/// is cleared when the socket goes down and nothing shows until `/list`
/// answers. Kept in memory: never written to SQLite.
class PresenceRepository extends GetxService with WidgetsBindingObserver {
  PresenceRepository(this._socket);

  final SocketService _socket;

  final online = <String>{}.obs;

  /// True once `/list` has answered on this connection.
  final isKnown = false.obs;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _socket.events.listen(_onEvent);
    _socket.onOnline.listen((_) => refresh());
    ever(_socket.connection, (state) {
      if (state == SocketState.online) return;
      online.clear();
      isKnown.value = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    if (_socket.isOnline) await _socket.sendCommand('/list');
  }

  /// Reads the Rx values it depends on, so call it inside an Obx.
  PresenceDot dotFor(String username) {
    final connection = _socket.connection.value;
    if (!isKnown.value || connection != SocketState.online) {
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
        isKnown.value = true;
      case 'presence':
        final user = idText(e['user']).toLowerCase();
        if (user.isEmpty) return;
        if (e['online'] == true) {
          online.add(user);
        } else {
          online.remove(user);
        }
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
