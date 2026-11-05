import 'push_payload.dart';

/// Where a push provider (FCM, later) plugs in. Nothing else in the app
/// knows which provider is behind it. The app uses [NoopPushService] until
/// the server has `push.register`.
abstract class PushService {
  Future<void> init();

  /// True when the person allowed notifications.
  Future<bool> requestPermission();

  /// The provider's token, each time it is issued or refreshed.
  Stream<String> get tokenStream;

  /// A push that arrived while the app runs.
  Stream<PushPayload> get onMessage;

  /// A push the person tapped (warm or cold start).
  Stream<PushPayload> get onOpened;

  /// Drops the token at the provider (sign out).
  Future<void> unregister();
}
