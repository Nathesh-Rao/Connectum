import 'package:connectum/core/selection/message_selection.dart';
import 'package:connectum/core/widgets/message_selection/selectable_row.dart';
import 'package:connectum/core/widgets/message_selection/swipe_to_reply.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _row = Key('row');

Widget _host({
  required Widget Function(Widget row) wrap,
  TextDirection dir = TextDirection.ltr,
  bool isReduced = false,
  double scale = 1,
  Widget? inner,
}) => MaterialApp(
  builder: (context, w) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: isReduced,
      textScaler: TextScaler.linear(scale),
    ),
    child: Directionality(textDirection: dir, child: w!),
  ),
  home: Scaffold(
    body: ListView(
      children: [
        wrap(
          inner ??
              const SizedBox(
                key: _row,
                height: 60,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('hi'),
                ),
              ),
        ),
        const SizedBox(height: 1200),
      ],
    ),
  ),
);

double _x(WidgetTester t) => t.getTopLeft(find.byKey(_row)).dx;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> reply(WidgetTester t, List<int> log, {Widget? inner}) =>
      t.pumpWidget(
        _host(
          inner: inner,
          wrap: (row) => SwipeToReply(onReply: () => log.add(1), child: row),
        ),
      );

  testWidgets('a drag past the threshold replies once and the row returns', (
    t,
  ) async {
    final log = <int>[];
    await reply(t, log);
    final g = await t.startGesture(const Offset(200, 30));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    expect(_x(t), greaterThan(40));
    expect(_x(t), lessThanOrEqualTo(SwipeReply.maxOffset));
    await g.up();
    await t.pumpAndSettle();
    expect(log, [1]);
    expect(_x(t), 0);
  });

  testWidgets('a drag below the threshold does nothing', (t) async {
    final log = <int>[];
    await reply(t, log);
    final g = await t.startGesture(const Offset(200, 30));
    await g.moveBy(const Offset(25, 0));
    await g.moveBy(const Offset(10, 0));
    await t.pump();
    expect(_x(t), greaterThan(0));
    await g.up();
    await t.pumpAndSettle();
    expect(log, isEmpty);
    expect(_x(t), 0);
  });

  testWidgets('a fast fling past the slop counts', (t) async {
    final log = <int>[];
    await reply(t, log);
    await t.fling(find.byKey(_row), const Offset(60, 0), 2000);
    await t.pumpAndSettle();
    expect(log, [1]);
  });

  testWidgets('rows that cannot be replied to do not move', (t) async {
    await t.pumpWidget(
      _host(wrap: (row) => SwipeToReply(onReply: null, child: row)),
    );
    final g = await t.startGesture(const Offset(200, 30));
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(40, 0));
    await t.pump();
    expect(_x(t), 0);
    await g.up();
  });

  testWidgets('selection mode disables the swipe', (t) async {
    final log = <int>[];
    final selection = MessageSelection()..ids.add('other');
    await t.pumpWidget(
      _host(
        wrap: (row) => SelectableRow(
          selection: selection,
          id: 'a',
          onSwipeReply: () => log.add(1),
          child: row,
        ),
      ),
    );
    final g = await t.startGesture(const Offset(200, 30));
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(40, 0));
    await t.pump();
    expect(_x(t), 0);
    await g.up();
    expect(log, isEmpty);
  });

  testWidgets('a diagonal drag scrolls the list and does not reply', (t) async {
    final log = <int>[];
    await reply(t, log);
    final g = await t.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(10, -60));
    await g.moveBy(const Offset(20, -60));
    await g.up();
    await t.pumpAndSettle();
    expect(log, isEmpty);
    expect(
      t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('a horizontal scroll inside the message wins', (t) async {
    final log = <int>[];
    final controller = ScrollController();
    await reply(
      t,
      log,
      inner: SizedBox(
        key: _row,
        height: 60,
        child: SingleChildScrollView(
          controller: controller,
          scrollDirection: Axis.horizontal,
          child: const SizedBox(width: 1200, height: 60),
        ),
      ),
    );
    final g = await t.startGesture(const Offset(300, 30));
    await g.moveBy(const Offset(-60, 0));
    await g.moveBy(const Offset(-60, 0));
    await g.up();
    await t.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(log, isEmpty);
    expect(_x(t), 0);
  });

  testWidgets('a drag from the start edge is left to the back gesture', (
    t,
  ) async {
    final log = <int>[];
    await reply(t, log);
    final g = await t.startGesture(const Offset(4, 30));
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await t.pumpAndSettle();
    expect(log, isEmpty);
  });

  testWidgets('right-to-left mirrors the direction', (t) async {
    final log = <int>[];
    await t.pumpWidget(
      _host(
        dir: TextDirection.rtl,
        wrap: (row) => SwipeToReply(onReply: () => log.add(1), child: row),
      ),
    );
    final g = await t.startGesture(const Offset(300, 30));
    await g.moveBy(const Offset(30, 0));
    await g.moveBy(const Offset(30, 0));
    await t.pump();
    expect(_x(t), 0, reason: 'moving the wrong way does not move the row');
    await g.moveBy(const Offset(-120, 0));
    await t.pump();
    expect(_x(t), lessThan(0));
    await g.up();
    await t.pumpAndSettle();
    expect(log, [1]);
  });

  testWidgets('reduced motion skips the spring', (t) async {
    await t.pumpWidget(
      _host(
        isReduced: true,
        wrap: (row) => SwipeToReply(onReply: () {}, child: row),
      ),
    );
    final g = await t.startGesture(const Offset(200, 30));
    await g.moveBy(const Offset(40, 0));
    await g.moveBy(const Offset(40, 0));
    await g.up();
    await t.pump();
    await t.pump(AppReduced.duration);
    expect(_x(t), 0);
  });

  testWidgets('a repliable row has the Reply semantic action', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      _host(
        scale: 1.5,
        wrap: (row) => SwipeToReply(onReply: () {}, child: row),
      ),
    );
    final data = t.getSemantics(find.byKey(_row)).getSemanticsData();
    expect(data.customSemanticsActionIds, isNotEmpty);
    expect(
      CustomSemanticsAction.getAction(
        data.customSemanticsActionIds!.first,
      )?.label,
      'Reply',
    );
    handle.dispose();
  });

  testWidgets('a row that cannot be replied to has no Reply action', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(
      _host(wrap: (row) => SwipeToReply(onReply: null, child: row)),
    );
    final data = t.getSemantics(find.byKey(_row)).getSemanticsData();
    expect(data.customSemanticsActionIds ?? const [], isEmpty);
    handle.dispose();
  });
}

class AppReduced {
  static const duration = Duration(milliseconds: 160);
}
