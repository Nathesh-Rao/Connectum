import '../../features/qr/models/qr_models.dart';
import '../socket/socket_service.dart';

/// The signed-in person's QR codes from `connect.my`. Fetched fresh on every
/// call: the code can be rotated from the web and no event says so.
class QrRepository {
  QrRepository(SocketService socket)
    : _fetch = (() => socket.sdCall('connect.my', const {}));

  /// A repository on any source of a `connect.my` answer (the debug samples).
  QrRepository.from(this._fetch);

  final Future<Map<String, dynamic>> Function() _fetch;

  Future<QrCodes> load() async => QrCodes.fromJson(await _fetch());
}
