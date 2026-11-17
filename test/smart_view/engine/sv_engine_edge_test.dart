import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/engine/sv_values.dart';
import 'package:flutter_test/flutter_test.dart';

EngineTable _t(
  List<Map<String, Object?>> rows, {
  EngineType type = EngineType.text,
}) => EngineTable([EngineCol('a', 'A', type)], rows);

void main() {
  group('values', () {
    test('empty and blank strings', () {
      expect(SvValues.isBlank(''), isTrue);
      expect(SvValues.isBlank('   '), isTrue);
      expect(SvValues.isBlank(0), isFalse);
      expect(SvValues.toNum(''), isNull);
      expect(SvValues.toTime('   '), isNull);
    });

    test('huge and odd numbers', () {
      expect(SvValues.toNum('1,234,567,890,123'), 1234567890123);
      expect(SvValues.toNum(double.infinity), isNull);
      expect(SvValues.toNum('.5'), isNull);
      expect(SvValues.toNum('1e5'), isNull);
      expect(SvValues.toNum('45%'), 45);
      expect(SvValues.toNum('-\$1,200.50'), -1200.5);
    });

    test('invalid dates', () {
      expect(SvValues.toTime('2026-02-30'), isNull);
      expect(SvValues.toTime('31/04/2026'), isNull);
      expect(SvValues.toTime('2026-11-12T25:00'), isNull);
      expect(SvValues.toTime('12.11.2026'), isNull);
      expect(SvValues.toTime('2024-02-29'), isNotNull);
    });

    test('unicode text keeps its form', () {
      expect(SvValues.plain('日本語'), '日本語');
      expect(SvValues.plain('Émile'), 'Émile');
    });
  });

  group('search and filters', () {
    final t = _t([
      {'a': 'Émile'},
      {'a': '日本語'},
      {'a': ''},
      {'a': null},
      {'a': 'plain'},
    ]);

    test('unicode search, no accent folding', () {
      expect(SvEngine.filter(t, search: '日本'), [1]);
      expect(SvEngine.filter(t, search: 'émile'), [0]);
      expect(SvEngine.filter(t, search: 'emile'), isEmpty);
    });

    test('whitespace-only search is inactive', () {
      expect(SvEngine.filter(t, search: '   '), [0, 1, 2, 3, 4]);
    });

    test('empty and filled count blanks and nulls alike', () {
      expect(
        SvEngine.filter(t, conditions: [const SvCondition('a', 'empty')]),
        [2, 3],
      );
      expect(
        SvEngine.filter(t, conditions: [const SvCondition('a', 'filled')]),
        [0, 1, 4],
      );
    });

    test('a filter never changes the table', () {
      final before = t.rows.map((r) => Map.of(r)).toList();
      SvEngine.filter(t, search: 'x');
      SvEngine.sort(t, [0, 1, 2], 'a', false);
      expect(t.rows, before);
    });

    test('unknown column matches nothing', () {
      expect(
        SvEngine.filter(
          t,
          conditions: [const SvCondition('zz', 'contains', 'x')],
        ),
        isEmpty,
      );
    });

    test('number between with a text cell does not match', () {
      final n = _t([
        {'a': 'abc'},
        {'a': 5},
        {'a': null},
      ], type: EngineType.number);
      expect(
        SvEngine.filter(
          n,
          conditions: [
            const SvCondition('a', 'between', {'from': 1, 'to': 10}),
          ],
        ),
        [1],
      );
    });

    test('date today uses the given now', () {
      final d = _t([
        {'a': '2026-11-17'},
        {'a': '2026-11-18'},
      ], type: EngineType.date);
      expect(
        SvEngine.filter(
          d,
          conditions: [const SvCondition('a', 'on', 'today')],
          now: DateTime(2026, 11, 18, 23, 59),
        ),
        [1],
      );
    });
  });

  group('sort', () {
    test('duplicates keep their order, both directions', () {
      final t = _t([
        {'a': 'x'},
        {'a': 'x'},
        {'a': 'b'},
        {'a': 'x'},
      ]);
      expect(SvEngine.sort(t, [0, 1, 2, 3], 'a', true), [2, 0, 1, 3]);
      expect(SvEngine.sort(t, [0, 1, 2, 3], 'a', false), [0, 1, 3, 2]);
    });

    test('blank and unparsable go last whichever direction', () {
      final t = _t([
        {'a': null},
        {'a': 3},
        {'a': 'zzz'},
        {'a': 1},
      ], type: EngineType.number);
      expect(SvEngine.sort(t, [0, 1, 2, 3], 'a', true), [3, 1, 0, 2]);
      expect(SvEngine.sort(t, [0, 1, 2, 3], 'a', false), [1, 3, 0, 2]);
    });

    test('numbers inside text compare as numbers; huge runs too', () {
      expect(SvEngine.compareText('item 2', 'item 10') < 0, isTrue);
      expect(
        SvEngine.compareText(
              'a99999999999999999999',
              'a100000000000000000000',
            ) <
            0,
        isTrue,
      );
    });

    test('digits before letters, accents with their base letter', () {
      expect(SvEngine.compareText('1', 'a') < 0, isTrue);
      expect(SvEngine.compareText('émile', 'f') < 0, isTrue);
      expect(SvEngine.compareText('émile', 'd') > 0, isTrue);
    });
  });

  group('inferType', () {
    test('huge numbers as numbers, ten digits as text', () {
      expect(SvValues.inferType([5e10, 2], 'Amount'), EngineType.number);
      expect(SvValues.inferType(['12345678901'], 'Amount'), EngineType.text);
    });

    test('invalid dates make a text column', () {
      expect(
        SvValues.inferType(['2026-02-30', '2026-11-12'], 'D'),
        EngineType.text,
      );
    });
  });
}
