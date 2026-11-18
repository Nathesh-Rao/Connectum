import 'dart:convert';
import 'dart:io';

import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/engine/sv_insights.dart';
import 'package:connectum/data/smart_view/engine/sv_values.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every case of the BE's `vectors.json` (the web's own output). A failure
/// names the case. The vectors were made in Asia/Calcutta: local-time cases
/// are checked as wall clock, so the run does not depend on this machine's
/// zone.
void main() {
  final v =
      jsonDecode(
            File(
              'test/fixtures/smart_view/engine/vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  EngineType typeOf(String s) =>
      EngineType.values.firstWhere((t) => t.name == s);

  final tableJson = v['table'] as Map<String, dynamic>;
  final table = EngineTable(
    [
      for (final c in tableJson['columns'] as List)
        EngineCol(c['key'], c['label'], typeOf(c['type'])),
    ],
    [
      for (final r in tableJson['rows'] as List)
        (r as Map).cast<String, Object?>(),
    ],
  );
  final all = List.generate(table.rows.length, (i) => i);

  SvCondition cond(Map c) => SvCondition(c['col'], c['op'], c['value']);

  group('toTime', () {
    for (final c in v['toTime'] as List) {
      test('${c['input']}', () {
        final got = SvValues.toTime(c['input']);
        final want = c['outputEpochMs'] as int?;
        final input = c['input'];
        final isLocal =
            input is String &&
            want != null &&
            !input.endsWith('Z') &&
            !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(input.split(' ').last) &&
            !input.contains('+');
        if (isLocal) {
          final ist = DateTime.parse(
            c['outputUtcIso'],
          ).add(const Duration(hours: 5, minutes: 30));
          final wall = DateTime(
            ist.year,
            ist.month,
            ist.day,
            ist.hour,
            ist.minute,
            ist.second,
            ist.millisecond,
          ).millisecondsSinceEpoch;
          expect(got, wall, reason: 'toTime ${c['input']}');
        } else {
          expect(got, want, reason: 'toTime ${c['input']}');
        }
      });
    }
  });

  group('inferType', () {
    for (final c in v['inferType'] as List) {
      test(c['label'], () {
        final i = c['input'] as Map;
        expect(
          SvValues.inferType(i['values'] as List, i['name']).name,
          c['output'],
          reason: 'inferType ${c['label']}',
        );
      });
    }
  });

  group('plain', () {
    for (final c in v['plain'] as List) {
      test('${c['input']}', () {
        expect(SvValues.plain(c['input']), c['output']);
      });
    }
  });

  group('filters', () {
    for (final c in v['filters'] as List) {
      test(c['label'], () {
        final i = c['input'] as Map;
        final searchIn = i['searchIn'] as List?;
        final got = SvEngine.filter(
          table,
          search: (i['search'] as String?) ?? '',
          searchIn: searchIn == null
              ? null
              : [for (final s in searchIn) table.col(s['key'])!],
          conditions: [for (final f in (i['filters'] as List?) ?? []) cond(f)],
        );
        expect(got, c['outputRowIndexes'], reason: 'filters ${c['label']}');
      });
    }
  });

  group('sort', () {
    for (final c in v['sort'] as List) {
      test(c['label'], () {
        final i = c['input'] as Map?;
        final got = i == null
            ? all
            : SvEngine.sort(table, all, i['col'], i['dir'] == 'asc');
        expect(got, c['outputRowIndexes'], reason: 'sort ${c['label']}');
      });
    }
  });

  group('group', () {
    for (final c in v['group'] as List) {
      test(c['label'], () {
        final i = c['input'] as Map;
        var got = SvEngine.group(
          table,
          all,
          (i['keys'] as List).cast<String>(),
          sumKey: i['sumKey'] as String?,
          closed: {
            for (final k in ((i['closed'] as Map?) ?? {}).keys) k as String,
          },
        );
        final want = c['output'] as List;
        // The "date column" vector lists only the group lines (no rows).
        if (!want.any((w) => (w as Map).containsKey('row'))) {
          got = [
            for (final g in got)
              if (g.isGroup) g,
          ];
        }
        expect(got.length, want.length, reason: 'group ${c['label']}');
        for (var n = 0; n < want.length; n++) {
          final w = want[n] as Map;
          final g = got[n];
          expect(g.depth, w['depth'], reason: '${c['label']} #$n');
          if (w.containsKey('row')) {
            expect(g.row, w['row'], reason: '${c['label']} #$n');
          } else {
            expect(g.group, w['group'], reason: '${c['label']} #$n');
            expect(g.path, w['path'], reason: '${c['label']} #$n');
            expect(g.count, w['count'], reason: '${c['label']} #$n');
            expect(g.sum, w['sum'], reason: '${c['label']} #$n');
            expect(g.open, w['open'], reason: '${c['label']} #$n');
          }
        }
      });
    }
  });

  group('aggregate', () {
    for (final c in v['aggregate'] as List) {
      test('${c['input']}', () {
        final i = c['input'] as Map;
        expect(
          SvEngine.aggregate(table, all, i['key'], i['agg']),
          closeTo((c['output'] as num).toDouble(), 1e-9),
        );
      });
    }
    for (final c in v['aggregateEmpty'] as List) {
      test('empty ${c['input']['agg']}', () {
        final i = c['input'] as Map;
        expect(SvEngine.aggregate(table, [], i['key'], i['agg']), 0);
      });
    }
  });

  group('isMeasure', () {
    for (final c in v['isMeasure'] as List) {
      test('${c['input']['label']} ${c['input']['type']}', () {
        final i = c['input'] as Map;
        expect(
          SvValues.isMeasure(i['key'], i['label'], typeOf(i['type'])),
          c['output'],
        );
      });
    }
  });

  test('summarise: rows, sum, avg and n of the measure column', () {
    final s = v['summarise']['output'] as Map;
    expect(table.rows.length, s['rows']);
    final m = (s['sums'] as List).single as Map;
    final col = table.col(m['key'])!;
    expect(SvValues.isMeasure(col.key, col.label, col.type), isTrue);
    expect(SvEngine.aggregate(table, all, 'qty', 'sum'), m['sum']);
    expect(
      SvEngine.aggregate(table, all, 'qty', 'avg'),
      closeTo((m['avg'] as num).toDouble(), 1e-9),
    );
    expect(SvEngine.aggregate(table, all, 'qty', 'count'), m['n']);
  });

  group('chips', () {
    for (final c in v['chips'] as List) {
      test(c['output'], () {
        final i = c['input'] as Map;
        final col = table.col(i['col'])!;
        expect(SvEngine.chipText(cond(i), col.label), c['output']);
      });
    }
  });

  group('filterControl', () {
    for (final c in v['filterControl'] as List) {
      test('${c['input']['key']}', () {
        final i = c['input'] as Map;
        final col = EngineCol(i['key'], i['label'], typeOf(i['type']));
        expect(SvEngine.controlFor(col), c['output']);
      });
    }
  });

  test('date presets, week Monday to Sunday', () {
    final r = v['datePresets']['output'] as Map;
    final got = SvEngine.rangeFor(DateTime(2026, 11, 18, 15));
    for (final k in r.keys) {
      expect(got[k]!.from, r[k]['from'], reason: 'preset $k from');
      expect(got[k]!.to, r[k]['to'], reason: 'preset $k to');
    }
    final sunday = v['datePresetsSunday']['output']['week'] as Map;
    final w = SvEngine.rangeFor(DateTime(2026, 11, 22))['week']!;
    expect(w.from, sunday['from']);
    expect(w.to, sunday['to']);
  });

  group('definedCards and definedChart', () {
    test('definedCards', () {
      final c = v['definedCards'] as Map<String, dynamic>;
      final got = SvInsights.definedCards(table, all, [
        for (final d in c['input'] as List) (d as Map).cast<String, Object?>(),
      ]);
      final want = c['output'] as List;
      expect(got.length, want.length);
      for (var i = 0; i < want.length; i++) {
        final w = want[i] as Map;
        expect(got[i].id, w['id']);
        expect(got[i].label, w['label']);
        expect(got[i].value, closeTo((w['value'] as num).toDouble(), 1e-9));
        expect(got[i].hasDecimals, w['decimals']);
        expect(got[i].tone, w['tone']);
        expect(got[i].icon, w['icon']);
      }
    });

    test('definedChart', () {
      final c = v['definedChart'] as Map<String, dynamic>;
      final got = SvInsights.definedChart(
        table,
        all,
        (c['input'] as Map).cast<String, Object?>(),
      )!;
      final w = c['output'] as Map;
      expect(got.type, w['type']);
      expect(got.title, w['title']);
      expect(got.subtitle, w['subtitle']);
      expect(got.labels, w['labels']);
      final series = (w['series'] as List).single as Map;
      expect(got.name, series['name']);
      expect(got.values, series['values']);
      expect(got.more, w['more']);
    });
  });

  test('vector counts', () {
    var n = 0;
    for (final k in [
      'toTime',
      'inferType',
      'plain',
      'filters',
      'sort',
      'group',
      'aggregate',
      'aggregateEmpty',
      'isMeasure',
      'chips',
      'filterControl',
    ]) {
      n += (v[k] as List).length;
    }
    // ignore: avoid_print
    print('VECTOR CASES RUN: ${n + 3} (incl. summarise and 2 date presets)');
  });
}
