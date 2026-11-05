import 'push_payload.dart';
import 'push_service.dart';

/// The push service of an app with no push provider: never has a token and
/// never receives anything.
class NoopPushService implements PushService {
  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Stream<String> get tokenStream => const Stream.empty();

  @override
  Stream<PushPayload> get onMessage => const Stream.empty();

  @override
  Stream<PushPayload> get onOpened => const Stream.empty();

  @override
  Future<void> unregister() async {}
}
