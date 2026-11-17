import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/engine/sv_values.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('5,000 synthetic rows: filter + sort timing', () {
    final cols = [
      const EngineCol('name', 'Name', EngineType.text),
      const EngineCol('qty', 'Qty', EngineType.number),
      const EngineCol('day', 'Day', EngineType.date),
      const EngineCol('stage', 'Stage', EngineType.text),
      const EngineCol('note', 'Note', EngineType.text),
    ];
    final rows = [
      for (var i = 0; i < 5000; i++)
        {
          'name': 'Customer ${(i * 7919) % 5000}',
          'qty': (i * 31) % 997,
          'day':
              '2026-${(i % 12 + 1).toString().padLeft(2, '0')}-${(i % 27 + 1).toString().padLeft(2, '0')}',
          'stage': ['Open', 'Closed', 'Waiting', 'Done'][i % 4],
          'note': i % 5 == 0 ? '' : 'Some longer free text for row $i',
        },
    ];
    final t = EngineTable(cols, rows);
    final conds = [
      const SvCondition('qty', 'gte', 100),
      const SvCondition('stage', 'in', ['Open', 'Done']),
      const SvCondition('day', 'between', {
        'from': '2026-03-01',
        'to': '2026-10-31',
      }),
    ];
    // Warm up, then measure the median of 9 runs.
    SvEngine.sort(
      t,
      SvEngine.filter(t, search: 'cust', conditions: conds),
      'name',
      true,
    );
    final times = <int>[];
    var n = 0;
    for (var r = 0; r < 9; r++) {
      final sw = Stopwatch()..start();
      final f = SvEngine.filter(t, search: 'cust', conditions: conds);
      final s = SvEngine.sort(t, f, 'name', true);
      sw.stop();
      n = s.length;
      times.add(sw.elapsedMicroseconds);
    }
    times.sort();
    // ignore: avoid_print
    print(
      'PERF filter+sort 5000 rows: median ${times[4] / 1000} ms, '
      'worst ${times.last / 1000} ms, $n rows out',
    );
    expect(n, greaterThan(0));
    expect(times[4], lessThan(2000000));
  });
}
