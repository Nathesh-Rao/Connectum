import 'ai_models.dart';

/// The in-chat AI. The only interface in the app: the real calls and the
/// fake of the debug page and the tests both fit it.
abstract class AiRepository {
  /// Fires when the list of agents may have changed (the server pushed
  /// `ai_agents_changed`, or the socket came back).
  Stream<void> get agentsChanged;

  /// Throws [AiError] when the list cannot be read.
  Future<AiSetup> getSetupState();

  /// One final event with the whole summary; failures arrive as an [AiError]
  /// on the stream. Cancelling the subscription drops a late answer.
  Stream<AiSummaryChunk> summarize(AiSummaryRequest request);

  /// The server has no cancel: this only makes the late answer unwanted.
  void cancel();
}
