import 'dart:async';

import 'ai_models.dart';
import 'ai_repository.dart';

enum FakeAiScenario {
  short,
  long,
  markdown,
  failure,
  chartBar,
  chartColumn,
  chartLine,
  chartDonut,
  chartMulti,
  chartMultiLine,
  chartMalformed,
  chartMany,
  chartManyBars,
  chartEdge,
}

String _fence(String json) => '```chart\n$json\n```';

/// Chart answers of the debug page: the same JSON the model writes.
final fakeChartSamples = <FakeAiScenario, String>{
  FakeAiScenario.chartBar:
      'Bangalore leads.\n\n'
      '${_fence('{"type":"bar","title":"Employees by city","unit":"people","data":[{"label":"Bangalore","value":22},{"label":"Chennai","value":13},{"label":"Pune","value":9},{"label":"Hyderabad","value":1250}]}')}\n\n'
      'Most people work in Bangalore.',
  FakeAiScenario.chartColumn:
      '${_fence('{"type":"column","title":"Revenue","unit":"lakh","data":[{"label":"Jan","value":12.5},{"label":"Feb","value":18},{"label":"Mar","value":9.25},{"label":"Apr","value":21}]}')}\n\nFebruary and April were the best months.',
  FakeAiScenario.chartLine:
      '${_fence('{"type":"line","title":"Tickets closed","unit":"tickets","data":[{"label":"Mon","value":4},{"label":"Tue","value":7},{"label":"Wed","value":6},{"label":"Thu","value":11},{"label":"Fri","value":9}]}')}\n\nClosures peaked on Thursday.',
  FakeAiScenario.chartDonut:
      '${_fence('{"type":"donut","title":"Leave by type","unit":"days","data":[{"label":"Casual","value":40},{"label":"Sick","value":25},{"label":"Earned","value":30},{"label":"Other","value":5}]}')}\n\nCasual leave is the largest share.',
  FakeAiScenario.chartMulti:
      '${_fence('{"type":"column","title":"Sales by quarter","unit":"lakh","labels":["Q1","Q2","Q3","Q4"],"series":[{"name":"2025","data":[10,14,12,18]},{"name":"2026","data":[13,16,15,22]}]}')}\n\n2026 is ahead in every quarter.',
  FakeAiScenario.chartMultiLine: _fence(
    '{"type":"line","title":"Visits","labels":["Jan","Feb","Mar","Apr"],"series":[{"name":"North","data":[5,8,6,9]},{"name":"South","data":[3,4,7,8]},{"name":"West","data":[2,6,5,4]}]}',
  ),
  FakeAiScenario.chartMalformed:
      'Before.\n\n${_fence('{"type":"bar","data":[')}\n\n'
      '```python\nprint(1)\n```\n\nAfter. The broken chart above shows nothing.',
  FakeAiScenario.chartMany: _fence(
    '{"type":"column","title":"Orders per month","unit":"orders","data":[{"label":"January","value":120},{"label":"February","value":90},{"label":"March","value":150},{"label":"April","value":130},{"label":"May","value":170},{"label":"June","value":160},{"label":"July","value":110},{"label":"August","value":140},{"label":"September","value":180},{"label":"October","value":190},{"label":"November","value":175},{"label":"December","value":210}]}',
  ),
  FakeAiScenario.chartManyBars: _fence(
    '{"type":"bar","title":"Tickets by team","unit":"tickets","data":[${List.generate(15, (i) => '{"label":"Team number ${i + 1}","value":${(15 - i) * 3}}').join(',')}]}',
  ),
  FakeAiScenario.chartEdge:
      '${_fence('{"type":"column","title":"A very long chart title that goes on and on","unit":"units","data":[{"label":"A label that is far too long to fit","value":-5},{"label":"Zero","value":0},{"label":"Big","value":9000000000000},{"label":"Text","value":"1,250"},{"label":"Skipped","value":"abc"}]}')}\n\n${_fence('{"type":"bar","data":[{"label":"All zero","value":0},{"label":"Also zero","value":0}]}')}',
};

const _short =
    'The team agreed to ship on Friday. Priya owns the release notes.';

const _markdown =
    '## Summary\n'
    'The team **agreed to ship on Friday**.\n\n'
    '## Decisions\n'
    '- Release on Friday\n'
    '- Keep the old login for one more week\n\n'
    '## Open\n'
    '1. Who tells the customers?\n'
    '2. Is the **data export** ready?\n\n'
    '## Actions\n'
    '- Priya: release notes\n'
    '- Sam: test the export';

String _long() => List.generate(
  14,
  (i) =>
      'Point ${i + 1}: the team talked about the plan, the owners and what is '
      'still open, and agreed to look at it again next week.',
).join('\n\n');

/// Answers in place of the server. The switches are plain fields the debug
/// page changes.
class FakeAiRepository implements AiRepository {
  FakeAiRepository({
    this.setup = const AiSetup(
      AiSetupState.ready,
      agents: [AiAgent(id: 'claude', name: 'Claude', provider: 'anthropic')],
    ),
    this.scenario = FakeAiScenario.markdown,
    this.delay = const Duration(milliseconds: 600),
  });

  AiSetup setup;
  FakeAiScenario scenario;
  Duration delay;

  /// What [FakeAiScenario.failure] ends in.
  AiErrorKind failure = AiErrorKind.failed;

  /// Fails the setup call instead of answering it.
  AiErrorKind? setupFailure;

  /// Sends the text in pieces before the final event (the real server never
  /// does; the debug page keeps it to preview the progressive view).
  bool isStreaming = false;

  int setupCalls = 0;
  int summarizeCalls = 0;
  int cancelCalls = 0;
  AiSummaryRequest? lastRequest;
  StreamController<AiSummaryChunk>? _open;
  final _changed = StreamController<void>.broadcast();

  @override
  Stream<void> get agentsChanged => _changed.stream;

  void changeAgents() => _changed.add(null);

  @override
  Future<AiSetup> getSetupState() async {
    setupCalls++;
    final failed = setupFailure;
    if (failed != null) throw AiError(failed);
    return setup;
  }

  @override
  Stream<AiSummaryChunk> summarize(AiSummaryRequest request) {
    summarizeCalls++;
    lastRequest = request;
    final controller = StreamController<AiSummaryChunk>();
    _open = controller;
    unawaited(_run(controller));
    return controller.stream;
  }

  Future<void> _run(StreamController<AiSummaryChunk> out) async {
    await Future<void>.delayed(delay);
    if (out.isClosed) return;
    if (scenario == FakeAiScenario.failure) {
      out.addError(AiError(failure));
      await out.close();
      return;
    }
    final text = switch (scenario) {
      FakeAiScenario.long => _long(),
      FakeAiScenario.markdown => _markdown,
      final chart when fakeChartSamples.containsKey(chart) =>
        fakeChartSamples[chart]!,
      _ => _short,
    };
    if (isStreaming) {
      final half = text.length ~/ 2;
      out.add(AiSummaryChunk(text.substring(0, half)));
      await Future<void>.delayed(delay);
      if (out.isClosed) return;
    }
    out.add(
      AiSummaryChunk(
        text,
        isFinal: true,
        messageCount: 42,
        isTruncated: lastRequest?.isCare ?? false,
      ),
    );
    await out.close();
  }

  @override
  void cancel() {
    cancelCalls++;
    _open?.close();
    _open = null;
  }
}
