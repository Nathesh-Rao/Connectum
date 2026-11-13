import '../data/ai/ai_models.dart';
import '../data/ai/fake_ai_repository.dart';

/// Canned summaries in turn: a plain one, one with a chart, an error and a
/// short one. A care thread question reads the canned team thread offline.
class DemoAiRepository extends FakeAiRepository {
  DemoAiRepository() : super(delay: const Duration(milliseconds: 900)) {
    care = FakeCareThread.team;
  }

  static const _turns = [
    FakeAiScenario.markdown,
    FakeAiScenario.chartBar,
    FakeAiScenario.failure,
    FakeAiScenario.short,
  ];

  /// Care questions in turn: an answer, the empty thread, no thread yet.
  static const _careTurns = [
    FakeCareThread.team,
    FakeCareThread.empty,
    FakeCareThread.notFound,
  ];
  int _careAsked = 0;

  @override
  Stream<AiSummaryChunk> summarize(AiSummaryRequest request) {
    if (request.isCare) care = _careTurns[_careAsked++ % _careTurns.length];
    scenario = _turns[summarizeCalls % _turns.length];
    return super.summarize(request);
  }
}
