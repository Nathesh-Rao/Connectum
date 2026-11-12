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

  @override
  Stream<AiSummaryChunk> summarize(AiSummaryRequest request) {
    scenario = _turns[summarizeCalls % _turns.length];
    return super.summarize(request);
  }
}
