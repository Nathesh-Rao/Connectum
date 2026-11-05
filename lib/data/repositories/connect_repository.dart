import 'package:get/get.dart';

import '../../core/debug/seed_connect.dart';
import '../../core/debug/seed_ui.dart';
import '../../core/utils/connect_code.dart';
import '../models/connect_lookup.dart';
import '../socket/socket_service.dart';

/// `connect.lookup` (who is this, connects nothing) and `connect.scan`
/// (connects). Both take the whole link and share one server limit.
class ConnectRepository extends GetxService {
  ConnectRepository(this._socket);

  final SocketService _socket;

  Future<ConnectLookup> lookup(ConnectCode target) => _call(target, 'lookup');

  Future<ConnectLookup> scan(ConnectCode target) => _call(target, 'scan');

  Future<ConnectLookup> _call(ConnectCode target, String action) async {
    if (SeedUi.isActive) {
      return SeedConnect.target(target, isScan: action == 'scan');
    }
    final data = await _socket.sdCall('connect.$action', {
      'code': target.linkText,
    });
    return ConnectLookup.fromJson(data);
  }
}
