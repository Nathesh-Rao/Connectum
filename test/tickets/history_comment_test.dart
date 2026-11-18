import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/features/tickets/widgets/history_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(String text, {String key = 'h-1-remarks', double width = 300}) =>
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: HistoryQuote(text: text, storageKey: key),
          ),
        ),
      ),
    );

final _long = List.filled(60, 'remark').join(' ');

void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(HistoryQuote.openKeys.clear);

  testWidgets('a text of up to four lines has no See more', (t) async {
    await t.pumpWidget(_host('Short one'));
    final line = t.getSize(find.text('Short one')).height;
    expect(find.text('Short one'), findsOneWidget);
    expect(find.text('See more'), findsNothing);
    // exactly four lines is still "not longer than four"
    final four = List.filled(4, 'x' * 10).join(' ');
    await t.pumpWidget(_host(four, width: 300));
    expect(t.getSize(find.text(four)).height, closeTo(line * 4, 1));
    expect(find.text('See more'), findsNothing);
    final five = List.filled(5, 'x' * 10).join(' ');
    await t.pumpWidget(_host(five, width: 300));
    expect(find.text('See more'), findsOneWidget);
  });

  testWidgets('a text of more than four lines shows See more, clamped', (
    t,
  ) async {
    await t.pumpWidget(_host('Short one'));
    final line = t.getSize(find.text('Short one')).height;
    await t.pumpWidget(_host(_long));
    expect(find.text('See more'), findsOneWidget);
    expect(t.getSize(find.text(_long)).height, closeTo(line * 4, 1));
  });

  testWidgets('See more opens it, See less closes it', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_long));
    final clamped = t.getSize(find.text(_long)).height;
    await t.tap(find.text('See more'));
    await _settle(t);
    expect(find.text('See less'), findsOneWidget);
    expect(t.getSize(find.text(_long)).height, greaterThan(clamped));
    await t.tap(find.text('See less'));
    await _settle(t);
    expect(find.text('See more'), findsOneWidget);
    expect(t.getSize(find.text(_long)).height, closeTo(clamped, 1));
  });

  testWidgets('an opened comment stays open after a rebuild', (t) async {
    _tall(t);
    await t.pumpWidget(_host(_long));
    await t.tap(find.text('See more'));
    await _settle(t);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(_host(_long));
    expect(find.text('See less'), findsOneWidget);
    // another item of the history is not affected
    await t.pumpWidget(_host(_long, key: 'h-2-remarks'));
    expect(find.text('See more'), findsOneWidget);
  });

  testWidgets('there is no container, no border and no scrollable', (t) async {
    await t.pumpWidget(_host(_long));
    final q = find.byType(HistoryQuote);
    expect(
      find.descendant(of: q, matching: find.byType(Scrollable)),
      findsNothing,
    );
    expect(
      find.descendant(of: q, matching: find.byType(SelectableText)),
      findsNothing,
    );
    expect(
      find.descendant(of: q, matching: find.byType(CircleAvatar)),
      findsNothing,
    );
    expect(find.descendant(of: q, matching: find.byType(Icon)), findsNothing);
    final dot = find.descendant(
      of: q,
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(dot, findsOneWidget);
    expect(t.getSize(dot), const Size(8, 8));
    expect(
      (t.widget<DecoratedBox>(dot).decoration as BoxDecoration).color,
      AppColors.cardMuted,
    );
    expect(t.getTopLeft(find.text(_long)).dx - t.getTopRight(dot).dx, 10);
  });
}
