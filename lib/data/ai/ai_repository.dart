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

  /// `care.thread {person}`, then the newest pages of that group's history
  /// and the team: the whole thread for a typed question, within 400
  /// messages / 70,000 characters (oldest dropped first, the block header
  /// says so). Throws [AiError]: `careNotFound` or `careNotStarted` for
  /// `not_found` (by code), `serverTimeout` when the history did not arrive.
  Future<CareThread> careThread(String person);

  /// The server has no cancel: this only makes the late answer unwanted.
  void cancel();
}
