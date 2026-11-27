import '../../features/qr/models/qr_models.dart';
import 'package:connectum/data/socket/socket.dart';

/// The signed-in person's QR codes from `connect.my`. Fetched fresh on every
/// call: the code can be rotated from the web and no event says so.
class QrRepository {
  QrRepository(SocketService socket)
    : _fetch = (() => socket.sdCall('connect.my', const {})),
      _rotate = (() => socket.sdCall('connect.rotate', const {}));

  /// A repository on any source of a `connect.my` answer (the debug samples
  /// and tests).
  QrRepository.from(
    this._fetch, {
    Future<Map<String, dynamic>> Function()? rotate,
  }) : _rotate = rotate;

  final Future<Map<String, dynamic>> Function() _fetch;
  final Future<Map<String, dynamic>> Function()? _rotate;

  Future<QrCodes> load() async => QrCodes.fromJson(await _fetch());

  /// `connect.rotate`: a new personal code; the old one stops working at once.
  Future<void> regenerate() async {
    final rotate = _rotate;
    if (rotate == null) throw StateError('regenerate is not available');
    await rotate();
  }
}
