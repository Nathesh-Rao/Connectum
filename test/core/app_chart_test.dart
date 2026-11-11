import 'dart:math' as math;
import 'dart:io';

import 'package:connectum/core/theme/app_chart_colors.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/app_chart/app_chart.dart';
import 'package:connectum/core/widgets/app_chart/app_chart_data.dart';
import 'package:connectum/data/ai/ai_answer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _single =
    '{"type":"bar","title":"Employees by city","unit":"people","data":[{"label":"Bangalore","value":22},{"label":"Chennai","value":13}]}';
const _multi =
    '{"type":"column","title":"Sales","unit":"lakh","labels":["Q1","Q2","Q3"],"series":[{"name":"2025","data":[10,14,12]},{"name":"2026","data":[13,16,"1,500"]}]}';

AppChartData chart(String json) => AppChartData.parse(json)!;

Future<void> loadFonts() async {
  final loader = FontLoader('PlusJakartaSans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/PlusJakartaSans-$w.ttf').readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
    );
  }
  await loader.load();
}

Widget host(
  Widget child, {
  double width = 360,
  double scale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(scale),
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(
      backgroundColor: AppColors.surface,
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ),
  ),
);

String columnJson(int n) =>
    '{"type":"column","unit":"x","data":[${List.generate(n, (i) => '{"label":"Month ${i + 1}","value":${i + 3}}').join(',')}]}';

void main() {
  group('the parser', () {
    test('a single series', () {
      final d = chart(_single);
      expect(d.type, AppChartType.bar);
      expect(d.title, 'Employees by city');
      expect(d.unit, 'people');
      expect(d.labels, ['Bangalore', 'Chennai']);
      expect(d.series.single.values, [22, 13]);
      expect(d.isMulti, isFalse);
    });

    test('several series over the same labels', () {
      final d = chart(_multi);
      expect(d.type, AppChartType.column);
      expect(d.labels, ['Q1', 'Q2', 'Q3']);
      expect(d.series.map((s) => s.name), ['2025', '2026']);
      expect(d.series[1].values, [13, 16, 1500]);
      expect(d.isMulti, isTrue);
    });

    test('every type, pie is a donut, anything else draws bars', () {
      for (final (name, type) in [
        ('bar', AppChartType.bar),
        ('column', AppChartType.column),
        ('line', AppChartType.line),
        ('donut', AppChartType.donut),
        ('pie', AppChartType.donut),
        ('radar', AppChartType.bar),
      ]) {
        expect(
          chart('{"type":"$name","data":[{"label":"a","value":1}]}').type,
          type,
          reason: name,
        );
      }
      expect(
        chart('{"data":[{"label":"a","value":1}]}').type,
        AppChartType.bar,
      );
      expect(
        chart('{"type":7,"data":[{"label":"a","value":1}]}').type,
        AppChartType.bar,
      );
    });

    test('defaults: no title and no unit are empty', () {
      final d = chart('{"data":[{"label":"a","value":1}]}');
      expect(d.title, '');
      expect(d.unit, '');
    });

    test('a row can use name for label; bad rows are skipped', () {
      final d = chart(
        '{"data":[{"name":"a","value":"1,000"},{"label":"b","value":"x"},{"label":"","value":2},{"label":"c","value":null},{"label":"d","value":3}]}',
      );
      expect(d.labels, ['a', 'd']);
      expect(d.series.single.values, [1000, 3]);
    });

    test('limits: 40 labels, 6 series, text lengths', () {
      final many = chart(columnJson(60));
      expect(many.labels.length, 40);
      final series = List.generate(
        9,
        (i) => '{"name":"s$i","data":[1]}',
      ).join(',');
      expect(chart('{"labels":["a"],"series":[$series]}').series.length, 6);
      final long = chart(
        '{"title":"${'t' * 200}","unit":"${'u' * 50}","data":[{"label":"${'l' * 100}","value":1}]}',
      );
      expect(long.title.length, 120);
      expect(long.unit.length, 24);
      expect(long.labels.single.length, 60);
    });

    test('missing values in a series stay null, huge ones are skipped', () {
      final d = chart(
        '{"labels":["a","b","c"],"series":[{"name":"x","data":[1,null]},{"name":"y","data":[1e30,2,3]}]}',
      );
      expect(d.series[0].values, [1, null, null]);
      expect(d.series[1].values, [null, 2, 3]);
    });

    test('malformed or empty JSON is null', () {
      for (final bad in [
        '',
        '{"type":"bar","data":[',
        'not json',
        '[1,2]',
        '"text"',
        '{}',
        '{"data":[]}',
        '{"data":[{"label":"a","value":"x"}]}',
        '{"labels":["a"],"series":[{"name":"s","data":[null]}]}',
        '{"labels":[],"series":[{"name":"s","data":[]}]}',
      ]) {
        expect(AppChartData.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('nice ticks', () {
    test('start at zero with a round step', () {
      expect(AppChartData.niceTicks(0, 22), [0, 10, 20, 30]);
      expect(AppChartData.niceTicks(0, 100), [0, 25, 50, 75, 100]);
      expect(AppChartData.niceTicks(0, 8), [0, 2, 4, 6, 8]);
      expect(AppChartData.niceTicks(0, 0.4), [0, 0.1, 0.2, 0.3, 0.4]);
      expect(AppChartData.niceTicks(5, 9).first, 0);
    });

    test('all zero, negatives and huge values', () {
      expect(AppChartData.niceTicks(0, 0), [0, 0.25, 0.5, 0.75, 1]);
      expect(AppChartData.niceTicks(-5, 10), [-5, 0, 5, 10]);
      expect(AppChartData.niceTicks(-30, -10), [-30, -20, -10, 0]);
      final huge = AppChartData.niceTicks(0, 9e14);
      expect(huge.first, 0);
      expect(huge.last, greaterThanOrEqualTo(9e14));
      expect(huge.length, lessThanOrEqualTo(13));
      expect(AppChartData.niceTicks(double.nan, double.infinity), isNotEmpty);
    });

    test('the ticks cover the data', () {
      for (final max in [1.0, 3.0, 7.0, 13.0, 99.0, 1234.0, 0.07]) {
        final t = AppChartData.niceTicks(0, max);
        expect(t.last, greaterThanOrEqualTo(max), reason: '$max');
      }
    });
  });

  group('text', () {
    test('format like the web', () {
      expect(AppChartData.format(22), '22');
      expect(AppChartData.format(12.5), '12.5');
      expect(AppChartData.format(1.236), '1.24');
      expect(AppChartData.format(1250), '1,250');
      expect(AppChartData.format(1234567.89), '1,234,567.9');
      expect(AppChartData.format(-3), '-3');
    });

    test('a single series as lines', () {
      expect(
        chart(_single).toPlainText(),
        'Employees by city (people)\n- Bangalore: 22\n- Chennai: 13',
      );
    });

    test('several series have a name line each', () {
      expect(
        chart(_multi).toPlainText(),
        'Sales (lakh)\n2025\n- Q1: 10\n- Q2: 14\n- Q3: 12\n2026\n- Q1: 13\n- Q2: 16\n- Q3: 1,500',
      );
    });

    test('missing title or unit', () {
      expect(
        chart('{"data":[{"label":"a","value":1}]}').toPlainText(),
        '- a: 1',
      );
      expect(
        chart('{"title":"T","data":[{"label":"a","value":1}]}').toPlainText(),
        'T\n- a: 1',
      );
      expect(
        chart('{"unit":"kg","data":[{"label":"a","value":1}]}').toPlainText(),
        'Chart (kg)\n- a: 1',
      );
    });

    test('the description reads out the values', () {
      expect(
        chart(_single).describe(),
        'Bar chart: Employees by city. Bangalore: 22 people, Chennai: 13 people',
      );
      expect(
        chart('{"type":"line","data":[{"label":"a","value":1}]}').describe(),
        'Line chart. a: 1',
      );
      expect(
        chart(_multi).describe(),
        startsWith('Column chart: Sales. 2025. Q1: 10 lakh'),
      );
    });
  });

  group('the answer', () {
    test('splits into text and charts in order', () {
      final parts = AiAnswer.parts(
        'Before.\n\n```chart\n$_single\n```\n\nAfter.',
      );
      expect(parts.length, 3);
      expect(parts[0].text, 'Before.');
      expect(parts[1].chart!.title, 'Employees by city');
      expect(parts[2].text, 'After.');
    });

    test('a malformed or an open chart shows nothing', () {
      expect(AiAnswer.plain('a\n```chart\n{"type":"ba\n```\nb'), 'a\n\nb');
      expect(AiAnswer.plain('a\n```chart\n{"type":"ba'), 'a');
      expect(AiAnswer.plain('a\n```chart\n$_single'), 'a');
      expect(AiAnswer.parts('```chart\n{'), isEmpty);
    });

    test('other fences and plain text are kept', () {
      expect(
        AiAnswer.plain('```python\nprint(1)\n```'),
        '```python\nprint(1)\n```',
      );
      expect(AiAnswer.plain('no chart here'), 'no chart here');
      const ascii = '```\nBangalore | ████ 22\nChennai | ██ 13\n```';
      expect(AiAnswer.plain(ascii), ascii);
      expect(AiAnswer.parts(ascii).single.chart, isNull);
    });

    test('plain text carries the chart data in place', () {
      expect(
        AiAnswer.plain('Sales rose.\n\n```CHART\n$_single\n```\n\n- Done'),
        'Sales rose.\n\nEmployees by city (people)\n- Bangalore: 22\n- Chennai: 13\n\n- Done',
      );
    });
  });

  test('every series colour reads 3:1 on the card backgrounds', () {
    double lum(Color c) {
      double f(double v) => v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    double ratio(Color a, Color b) {
      final x = lum(a), y = lum(b);
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    expect(AppChartColors.series.first, AppChartColors.orange);
    for (final c in AppChartColors.series) {
      expect(ratio(c, AppColors.background), greaterThanOrEqualTo(3));
      expect(ratio(c, AppColors.surface), greaterThanOrEqualTo(3));
    }
  });

  group('the widget', () {
    testWidgets('draws every type, single and multi, without errors', (
      tester,
    ) async {
      for (final json in [
        _single,
        _multi,
        '{"type":"column","data":[{"label":"a","value":3}]}',
        '{"type":"line","data":[{"label":"a","value":3},{"label":"b","value":5}]}',
        '{"type":"line","labels":["a","b"],"series":[{"name":"x","data":[1,2]},{"name":"y","data":[2,1]}]}',
        '{"type":"donut","title":"T","data":[{"label":"a","value":3},{"label":"b","value":5}]}',
        '{"type":"bar","labels":["a","b"],"series":[{"name":"x","data":[1,2]},{"name":"y","data":[2,1]}]}',
      ]) {
        await tester.pumpWidget(host(AppChart(chart(json))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: json);
      }
    });

    testWidgets('negatives, zeros, text numbers and a huge value do not crash', (
      tester,
    ) async {
      for (final json in [
        '{"type":"column","data":[{"label":"n","value":-5},{"label":"z","value":0},{"label":"p","value":7}]}',
        '{"type":"bar","data":[{"label":"n","value":-5},{"label":"p","value":7}]}',
        '{"type":"line","data":[{"label":"n","value":-5},{"label":"p","value":7}]}',
        '{"type":"column","data":[{"label":"z","value":0},{"label":"y","value":0}]}',
        '{"type":"bar","data":[{"label":"z","value":0}]}',
        '{"type":"donut","data":[{"label":"z","value":0}]}',
        '{"type":"donut","data":[{"label":"n","value":-3},{"label":"p","value":2}]}',
        '{"type":"column","data":[{"label":"big","value":9e14},{"label":"s","value":1}]}',
        '{"type":"line","labels":["a","b","c"],"series":[{"name":"x","data":[1,null,3]}]}',
      ]) {
        await tester.pumpWidget(host(AppChart(chart(json))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: json);
      }
    });

    testWidgets('more than eight categories scroll sideways, bars stay 12 dp', (
      tester,
    ) async {
      await tester.pumpWidget(host(AppChart(chart(columnJson(14)))));
      await tester.pumpAndSettle();
      final scroll = find.byType(SingleChildScrollView).last;
      final state = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      expect(state.position.maxScrollExtent, greaterThan(0));
      await tester.drag(scroll, const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(state.position.pixels, greaterThan(0));
    });

    testWidgets('eight categories or fewer fit without scrolling', (
      tester,
    ) async {
      await tester.pumpWidget(host(AppChart(chart(columnJson(8)))));
      await tester.pumpAndSettle();
      final scroll = find.byType(SingleChildScrollView).last;
      final state = tester.state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      );
      expect(state.position.maxScrollExtent, 0);
    });

    testWidgets('many bars: 12 shown and "+N more"', (tester) async {
      final json =
          '{"type":"bar","data":[${List.generate(15, (i) => '{"label":"T$i","value":${i + 1}}').join(',')}]}';
      await tester.pumpWidget(host(AppChart(chart(json))));
      await tester.pumpAndSettle();
      expect(find.text('+3 more'), findsOneWidget);
      final custom = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter != null && w.size == Size.zero,
      );
      expect(custom, findsWidgets);
      final heights = tester.getSize(find.byType(AppChart)).height;
      expect(heights, greaterThan(12 * 28));
      await tester.pumpWidget(host(AppChart(chart(_single))));
      await tester.pumpAndSettle();
      expect(find.textContaining('more'), findsNothing);
    });

    testWidgets('long labels and titles at 2x text do not overflow', (
      tester,
    ) async {
      const long =
          'A label that is far too long to fit in any slot of the chart';
      for (final type in ['bar', 'column', 'line', 'donut']) {
        final json =
            '{"type":"$type","title":"$long $long","unit":"some long unit","data":[{"label":"$long","value":12},{"label":"Short","value":30},{"label":"$long 2","value":5}]}';
        for (final width in [320.0, 360.0]) {
          await tester.pumpWidget(
            host(AppChart(chart(json)), width: width, scale: 2),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$type $width');
        }
      }
      await tester.pumpWidget(
        host(
          AppChart(
            chart(
              '{"type":"line","labels":["$long","b"],"series":[{"name":"$long","data":[1,2]},{"name":"y","data":[2,1]}]}',
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'tapping a column shows its label and value, tapping again hides it',
      (tester) async {
        final data = chart(
          '{"type":"column","unit":"lakh","data":[{"label":"Jan","value":12.5},{"label":"Feb","value":18},{"label":"Mar","value":9},{"label":"Apr","value":21}]}',
        );
        await tester.pumpWidget(host(AppChart(data)));
        await tester.pumpAndSettle();
        expect(find.text('Jan: 12.5 lakh'), findsNothing);
        final plot = tester.getRect(find.byType(SingleChildScrollView).last);
        final tap = Offset(plot.left + plot.width / 8, plot.top + 165);
        await tester.tapAt(tap);
        await tester.pump();
        expect(find.text('Jan: 12.5 lakh'), findsOneWidget);
        await tester.tapAt(
          Offset(plot.left + plot.width * 3 / 8, plot.top + 165),
        );
        await tester.pump();
        expect(find.text('Jan: 12.5 lakh'), findsNothing);
        expect(find.text('Feb: 18 lakh'), findsOneWidget);
        await tester.tapAt(
          Offset(plot.left + plot.width * 3 / 8, plot.top + 165),
        );
        await tester.pump();
        expect(find.text('Feb: 18 lakh'), findsNothing);
      },
    );

    testWidgets('tapping a bar, a line point and a donut segment', (
      tester,
    ) async {
      await tester.pumpWidget(host(AppChart(chart(_single))));
      await tester.pumpAndSettle();
      final bars = tester.getRect(
        find.descendant(
          of: find.byType(AppChart),
          matching: find.byType(GestureDetector),
        ),
      );
      await tester.tapAt(Offset(bars.left + bars.width * 0.6, bars.top + 14));
      await tester.pump();
      expect(find.textContaining('Bangalore: 22 people'), findsOneWidget);

      await tester.pumpWidget(
        host(
          AppChart(
            chart(
              '{"type":"donut","unit":"d","data":[{"label":"Casual","value":3},{"label":"Sick","value":1}]}',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ring = tester.getRect(find.byType(CustomPaint).last);
      expect(ring.width, greaterThan(100));
      // 12 o'clock, just right of the top: the first segment.
      await tester.tapAt(Offset(ring.center.dx + 6, ring.top + 14));
      await tester.pump();
      expect(find.text('Casual: 3 d'), findsOneWidget);
    });

    testWidgets('grows in once, not again on a rebuild', (tester) async {
      final data = chart(_single);
      await tester.pumpWidget(host(AppChart(data, key: const Key('same'))));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(
        host(AppChart(data, key: const Key('same')), width: 361),
      );
      await tester.pumpWidget(
        host(AppChart(data, key: const Key('same')), width: 362),
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('does not animate when animations are off', (tester) async {
      await tester.pumpWidget(
        host(AppChart(chart(_single)), disableAnimations: true),
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('one semantics node with the description', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(AppChart(chart(_single))));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.byType(AppChart));
      expect(
        node.label,
        'Bar chart: Employees by city. Bangalore: 22 people, Chennai: 13 people',
      );
      expect(find.bySemanticsLabel(RegExp('Bangalore')), findsOneWidget);
      handle.dispose();
    });
  });

  group('goldens', () {
    setUpAll(loadFonts);

    final samples = <String, String>{
      'bar': _single,
      'column':
          '{"type":"column","title":"Revenue","unit":"lakh","data":[{"label":"Jan","value":12.5},{"label":"Feb","value":18},{"label":"Mar","value":9.25},{"label":"Apr","value":21}]}',
      'line':
          '{"type":"line","title":"Tickets closed","unit":"tickets","data":[{"label":"Mon","value":4},{"label":"Tue","value":7},{"label":"Wed","value":6},{"label":"Thu","value":11},{"label":"Fri","value":9}]}',
      'donut':
          '{"type":"donut","title":"Leave by type","unit":"days","data":[{"label":"Casual","value":40},{"label":"Sick","value":25},{"label":"Earned","value":30},{"label":"Other","value":5}]}',
      'multi':
          '{"type":"column","title":"Sales by quarter","unit":"lakh","labels":["Q1","Q2","Q3","Q4"],"series":[{"name":"2025","data":[10,14,12,18]},{"name":"2026","data":[13,16,15,22]}]}',
      'multi_line':
          '{"type":"line","title":"Visits","labels":["Jan","Feb","Mar","Apr"],"series":[{"name":"North","data":[5,8,6,9]},{"name":"South","data":[3,4,7,8]},{"name":"West","data":[2,6,5,4]}]}',
      'scroll': columnJson(12),
    };
    for (final width in [360.0, 412.0]) {
      for (final e in samples.entries) {
        testWidgets('${e.key} at ${width.toInt()} dp', (tester) async {
          tester.view.physicalSize = Size(width, 520);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('shot'),
              child: host(AppChart(chart(e.value)), width: width),
            ),
          );
          await tester.pumpAndSettle();
          await expectLater(
            find.byKey(const Key('shot')),
            matchesGoldenFile('goldens/chart_${e.key}_${width.toInt()}.png'),
          );
        });
      }
    }
  });
}
