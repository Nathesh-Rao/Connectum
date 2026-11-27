import 'package:connectum/core/selection/message_selection.dart';
import 'package:connectum/core/selection/selection_rules.dart';
import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/widgets/message_selection/selectable_row.dart';
import 'package:connectum/core/widgets/message_selection/selection_app_bar.dart';
import 'package:connectum/core/widgets/message_selection/selection_reaction_bar.dart';
import 'package:connectum/data/models/reaction.dart';
import 'package:connectum/features/conversation/widgets/emoji_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _size(
  WidgetTester t,
  Size size, {
  double scale = 1,
  TextDirection dir = TextDirection.ltr,
  required Widget child,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: dir, child: w!),
      ),
      home: Scaffold(body: child),
    ),
  );
  await t.pump();
}

List<SelectionBarItem> _items(
  List<SelectionAction> actions,
  List<String> log,
) => [
  for (final a in actions)
    SelectionBarItem(
      action: a,
      icon: Icons.circle,
      label: a.name,
      onTap: () => log.add(a.name),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('highlight', () {
    testWidgets('a selected row has the band; an unselected one does not', (
      t,
    ) async {
      final s = MessageSelection()..onLongPress('a');
      await _size(
        t,
        const Size(320, 640),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              SelectableRow(
                selection: s,
                id: 'a',
                child: const SizedBox(height: 40, width: double.infinity),
              ),
              SelectableRow(
                selection: s,
                id: 'b',
                child: const SizedBox(height: 40, width: double.infinity),
              ),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      final bands = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == AppColors.selectionTint,
      );
      expect(bands, findsNWidgets(2));
      double opacityOf(int i) => t
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: bands.at(i),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity;
      expect(opacityOf(0), 1);
      expect(opacityOf(1), 0);
      // The band runs past the row on both sides: the full width.
      final r = t.getRect(bands.first);
      expect(r.left, 0);
      expect(r.right, 320);
    });

    testWidgets('while selecting a tap toggles the row, not the child', (
      t,
    ) async {
      final s = MessageSelection()..onLongPress('a');
      var childTaps = 0;
      await _size(
        t,
        const Size(320, 640),
        child: Column(
          children: [
            for (final id in ['a', 'b'])
              SelectableRow(
                selection: s,
                id: id,
                child: GestureDetector(
                  onTap: () => childTaps++,
                  child: SizedBox(key: Key('row-$id'), height: 40, width: 200),
                ),
              ),
          ],
        ),
      );
      await t.tap(find.byKey(const Key('row-b')));
      await t.pump();
      expect(s.ids, ['a', 'b']);
      await t.tap(find.byKey(const Key('row-a')));
      await t.pump();
      expect(s.ids, ['b']);
      expect(childTaps, 0);
    });
  });

  group('selection bar', () {
    final actions = [
      SelectionAction.reply,
      SelectionAction.star,
      SelectionAction.delete,
      SelectionAction.forward,
      SelectionAction.copy,
      SelectionAction.pin,
      SelectionAction.edit,
    ];

    testWidgets('320 px, text scale 1.5: four icons plus More, no overflow', (
      t,
    ) async {
      final log = <String>[];
      await _size(
        t,
        const Size(320, 640),
        scale: 1.5,
        child: SelectionAppBar(
          count: 12,
          items: _items(actions, log),
          onExit: () => log.add('exit'),
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.text('12'), findsOneWidget);
      for (final a in ['reply', 'star', 'delete', 'forward']) {
        expect(find.byTooltip(a), findsOneWidget);
      }
      expect(find.byTooltip('copy'), findsNothing);
      expect(find.byTooltip('More'), findsOneWidget);
      await t.tap(find.byTooltip('More'));
      await t.pumpAndSettle();
      expect(find.text('copy'), findsOneWidget);
      expect(find.text('pin'), findsOneWidget);
      expect(find.text('edit'), findsOneWidget);
      await t.tap(find.text('pin'));
      await t.pumpAndSettle();
      expect(log, ['pin']);
    });

    testWidgets('every icon has a tooltip and a semantics label', (t) async {
      final handle = t.ensureSemantics();
      await _size(
        t,
        const Size(411, 640),
        child: SelectionAppBar(
          count: 1,
          items: _items(actions.take(5).toList(), []),
          onExit: () {},
        ),
      );
      for (final a in [
        'reply',
        'star',
        'delete',
        'forward',
        'Exit selection',
      ]) {
        expect(find.bySemanticsLabel(a), findsWidgets);
        expect(find.byTooltip(a), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('the back arrow exits', (t) async {
      final log = <String>[];
      await _size(
        t,
        const Size(320, 640),
        child: SelectionAppBar(
          count: 1,
          items: _items([SelectionAction.delete], log),
          onExit: () => log.add('exit'),
        ),
      );
      await t.tap(find.byTooltip('Exit selection'));
      expect(log, ['exit']);
    });

    testWidgets('right to left lays out without overflow', (t) async {
      await _size(
        t,
        const Size(320, 640),
        scale: 1.5,
        dir: TextDirection.rtl,
        child: SelectionAppBar(
          count: 3,
          items: _items(actions, []),
          onExit: () {},
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('reaction bar', () {
    Widget bar(List<String> log, {Set<String> mine = const {}}) =>
        SelectionReactionBar(
          emojis: Reaction.quick,
          mine: mine,
          onPick: log.add,
          onMore: () => log.add('+'),
        );

    testWidgets('a tap sends that emoji once', (t) async {
      final log = <String>[];
      await _size(t, const Size(411, 640), child: Center(child: bar(log)));
      await t.tap(find.text('😂'));
      expect(log, ['😂']);
    });

    testWidgets('my own reaction is marked selected', (t) async {
      final handle = t.ensureSemantics();
      await _size(
        t,
        const Size(411, 640),
        child: Center(child: bar([], mine: {'❤️'})),
      );
      expect(
        t.getSemantics(find.bySemanticsLabel('❤️')),
        matchesSemantics(
          label: '❤️',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasEnabledState: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('narrow: the emoji scroll and the plus stays visible', (
      t,
    ) async {
      final log = <String>[];
      await _size(
        t,
        const Size(320, 640),
        scale: 1.5,
        child: Center(child: SizedBox(width: 280, child: bar(log))),
      );
      expect(t.takeException(), isNull);
      expect(find.bySemanticsLabel('More reactions'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('More reactions'));
      expect(log, ['+']);
      await t.drag(find.byType(ListView), const Offset(-300, 0));
      await t.pump();
      expect(find.text('👏'), findsOneWidget);
    });

    group('placement', () {
      const screen = Size(360, 640);

      Future<Rect> place(
        WidgetTester t, {
        required double rowTop,
        bool isMine = true,
      }) async {
        final s = MessageSelection()..onLongPress('m');
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await _size(
          t,
          screen,
          child: Stack(
            children: [
              Positioned(
                top: rowTop,
                left: isMine ? 120 : 20,
                width: 220,
                height: 48,
                child: SelectableRow(
                  selection: s,
                  id: 'm',
                  child: const SizedBox(height: 48, width: 220),
                ),
              ),
              Positioned.fill(
                child: SelectionBarOverlay(
                  selection: s,
                  scroll: scroll,
                  isShown: () => true,
                  barWidth: SelectionReactionBar.idealWidth(7),
                  bar: (w) => SizedBox(
                    key: const Key('bar'),
                    height: SelectionReactionBar.height,
                    width: w,
                  ),
                ),
              ),
            ],
          ),
        );
        await t.pumpAndSettle();
        return t.getRect(find.byKey(const Key('bar')));
      }

      testWidgets('in the middle: above the message', (t) async {
        final r = await place(t, rowTop: 300);
        expect(r.bottom, lessThan(300));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(screen.width));
      });

      testWidgets('near the top: below the message', (t) async {
        final r = await place(t, rowTop: 8);
        expect(r.top, greaterThan(8 + 48 - 1));
      });

      testWidgets('near the bottom: still inside the screen', (t) async {
        final r = await place(t, rowTop: 600);
        expect(r.bottom, lessThanOrEqualTo(screen.height));
        expect(r.top, greaterThanOrEqualTo(0));
      });

      testWidgets('a scroll hides the bar and keeps the selection', (t) async {
        final s = MessageSelection()..onLongPress('m');
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await _size(
          t,
          screen,
          child: Stack(
            children: [
              Positioned(
                top: 300,
                left: 20,
                child: SelectableRow(
                  selection: s,
                  id: 'm',
                  child: const SizedBox(height: 48, width: 200),
                ),
              ),
              Positioned.fill(
                child: SelectionBarOverlay(
                  selection: s,
                  scroll: scroll,
                  isShown: () => true,
                  barWidth: 300,
                  bar: (w) =>
                      SizedBox(key: const Key('bar'), height: 52, width: w),
                ),
              ),
            ],
          ),
        );
        await t.pumpAndSettle();
        expect(find.byKey(const Key('bar')), findsOneWidget);
        s.hideBar();
        await t.pump();
        expect(find.byKey(const Key('bar')), findsNothing);
        expect(s.isActive, isTrue);
      });

      testWidgets('not shown when the rule says no (notes, two messages)', (
        t,
      ) async {
        final s = MessageSelection()..onLongPress('m');
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        await _size(
          t,
          screen,
          child: Stack(
            children: [
              SelectableRow(
                selection: s,
                id: 'm',
                child: const SizedBox(height: 48, width: 200),
              ),
              Positioned.fill(
                child: SelectionBarOverlay(
                  selection: s,
                  scroll: scroll,
                  isShown: () => false,
                  barWidth: 300,
                  bar: (w) =>
                      SizedBox(key: const Key('bar'), height: 52, width: w),
                ),
              ),
            ],
          ),
        );
        await t.pumpAndSettle();
        expect(find.byKey(const Key('bar')), findsNothing);
      });
    });
  });

  group('emoji picker', () {
    testWidgets('search narrows the list and a tap returns the emoji', (
      t,
    ) async {
      String? picked;
      await _size(
        t,
        const Size(411, 800),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await EmojiPickerSheet.show(context),
            child: const Text('open'),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(EditableText), 'rocket');
      await t.pumpAndSettle();
      expect(find.text('🚀'), findsOneWidget);
      expect(find.text('🔥'), findsNothing);
      await t.tap(find.text('🚀'));
      await t.pumpAndSettle();
      expect(picked, '🚀');
    });

    testWidgets('nothing found says so', (t) async {
      await _size(
        t,
        const Size(411, 800),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => EmojiPickerSheet.show(context),
            child: const Text('open'),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(EditableText), 'qqqq');
      await t.pumpAndSettle();
      expect(find.text('No emoji found'), findsOneWidget);
    });
  });
}
