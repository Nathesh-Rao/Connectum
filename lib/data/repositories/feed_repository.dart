import 'package:get/get.dart';

import '../models/ids.dart';
import '../socket/socket_service.dart';

/// The unread count of the workspace feed (`feed.summary`), kept fresh by the
/// `feed_item`, `feed_changed` and `feed_removed` events. In memory only: the
/// bell shows no dot until the first answer.
class FeedRepository extends GetxService {
  FeedRepository(this._socket);

  final SocketService _socket;

  final unread = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _socket.events.listen(_onEvent);
    _socket.onOnline.listen((_) => refresh());
  }

  Future<void> refresh() async {
    if (!_socket.isOnline) return;
    try {
      final data = await _socket.sdCall('feed.summary', {});
      unread.value = intOf(data['unread']);
    } on SocketCallError catch (_) {}
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'sd_event') return;
    final event = e['event'];
    if (event != 'feed_item' &&
        event != 'feed_changed' &&
        event != 'feed_removed') {
      return;
    }
    final counts = (e['data'] as Map?)?['counts'];
    if (counts is Map && counts['unread'] != null) {
      unread.value = intOf(counts['unread']);
    } else {
      refresh();
    }
  }
}
