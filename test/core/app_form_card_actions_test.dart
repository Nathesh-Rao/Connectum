import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_radius.dart';
import 'package:connectum/core/utils/chat_time.dart';
import 'package:connectum/core/widgets/app_action_bar.dart';
import 'package:connectum/core/widgets/app_form_card.dart';
import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/form_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _ts = DateTime(2026, 11, 5, 9, 30).millisecondsSinceEpoch;

final _card = FormCardData(
  id: '7',
  caption: 'Help ticket',
  structure: 'help_ticket',
  scope: 'user',
  by: 'bruno',
  ts: _ts,
  isTicket: true,
  entries: const [FormEntry(name: 'title', caption: 'Title', text: 'Printer')],
);

Widget _cardWith(int count, {bool isSent = false}) => AppFormCard(
  data: _card,
  isSent: isSent,
  statusMark: isSent ? const Icon(Icons.done_all, size: 14) : null,
  onTap: () {},
  actions: count == 0
      ? null
      : AppFormCardActionArea(
          child: AppActionBar(
            inset: AppFormCardActionArea.inset,
            onTap: (_) {},
            items: [
              for (var i = 0; i < count; i++)
                ActionItem(id: '$i', label: 'Action $i', icon: Icons.undo),
            ],
          ),
        ),
);

Widget _host(Widget child, {double width = 360, double textScale = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

Finder _body(Finder time) =>
    find.ancestor(of: time, matching: find.byType(ClipRRect)).first;

Rect _strip(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(AppFormCard),
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.color == AppColors.cardChip,
        ),
      )
      .last,
);

void main() {
  final time = find.text(ChatTime.time(_ts));
  final bar = find.byTooltip('More actions');

  for (final count in [0, 1, 2, 3, 6]) {
    testWidgets('$count actions: tight under the last thing, no overflow', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_cardWith(count)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(bar, count > 2 ? findsOneWidget : findsNothing);
      final card = tester.getRect(_body(time));
      if (count > 0) {
        // The time is inside the bottom strip, at the right, 16 dp in.
        final strip = _strip(tester);
        expect(tester.getRect(time).right, closeTo(card.right - 16, 1.5));
        expect(card.bottom, closeTo(strip.bottom, 0.01));
        expect(strip.height, AppActionBar.barHeight);
        expect(strip.left, closeTo(card.left, 0.01));
        expect(strip.right, closeTo(card.right, 0.01));
        expect(tester.getRect(time).bottom, lessThanOrEqualTo(strip.bottom));
        expect(tester.getRect(time).top, greaterThanOrEqualTo(strip.top));
        expect(find.text(ChatTime.time(_ts)), findsOneWidget);
      } else {
        // No actions: the plain row, 4 dp above and at most 8 dp below.
        expect(
          card.bottom - tester.getRect(time).bottom,
          lessThanOrEqualTo(8 + 4),
        );
      }
    });

    if (count > 2) {
      testWidgets('$count actions open: no overflow, narrow and large text', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(_cardWith(count), width: 220, textScale: 2),
        );
        await tester.pumpAndSettle();
        await tester.tap(bar);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Action ${count - 1}'), findsOneWidget);
      });
    }
  }

  testWidgets('opening a card does not move the bar in a reverse list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ListView(
          reverse: true,
          children: [_cardWith(6), const SizedBox(height: 600)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = tester.getRect(bar);
    final timeBefore = tester.getRect(time);
    await tester.tap(bar);
    await tester.pumpAndSettle();
    expect(tester.getRect(bar), before);
    expect(tester.getRect(time), timeBefore);
    expect(find.text('Action 5'), findsOneWidget);
  });

  testWidgets('the chevron respects disabled animations', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: _cardWith(4)),
        ),
      ),
    );
    await tester.tap(bar);
    await tester.pump();
    final turn = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation));
    expect(turn.duration, Duration.zero);
    expect(turn.turns, 0.5);
  });

  testWidgets('sent card: ticks sit beside the time inside the strip', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_cardWith(3, isSent: true)));
    await tester.pumpAndSettle();
    final tick = find.byIcon(Icons.done_all);
    expect(tick, findsOneWidget);
    final strip = _strip(tester);
    expect(strip.contains(tester.getCenter(tick)), isTrue);
    expect(tester.getRect(tick).left, greaterThan(tester.getRect(time).right));
  });

  for (final open in [false, true]) {
    testWidgets(
      'bottom corners are clipped with the card radius (open: $open)',
      (tester) async {
        await tester.pumpWidget(_host(_cardWith(6)));
        await tester.pumpAndSettle();
        if (open) {
          await tester.tap(bar);
          await tester.pumpAndSettle();
        }
        final clip = tester.widget<ClipRRect>(_body(time));
        expect(
          clip.borderRadius,
          const BorderRadius.all(Radius.circular(AppRadius.card - 1)),
        );
        final card = tester.getRect(_body(time));
        expect(card.bottom, closeTo(_strip(tester).bottom, 0.01));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('tapping the time toggles the bar', (tester) async {
    await tester.pumpWidget(_host(_cardWith(6)));
    await tester.pumpAndSettle();
    expect(find.text('Action 5'), findsNothing);
    await tester.tap(time);
    await tester.pumpAndSettle();
    expect(find.text('Action 5'), findsOneWidget);
    await tester.tap(time);
    await tester.pumpAndSettle();
    expect(find.text('Action 5'), findsNothing);
  });

  testWidgets('two or fewer: time-only strip, no chevron, not tappable', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_cardWith(2)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    final strip = find.byWidgetPredicate(
      (w) => w is Material && w.color == AppColors.cardChip,
    );
    expect(
      tester
          .widget<InkWell>(
            find.descendant(of: strip, matching: find.byType(InkWell)),
          )
          .onTap,
      isNull,
    );
  });

  testWidgets('the semantics label has the time', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_cardWith(3)));
    expect(
      find.bySemanticsLabel('More actions, ${ChatTime.time(_ts)}'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('360 dp and 2x text: no overflow, strip still last', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_cardWith(6, isSent: true), textScale: 2));
    await tester.pumpAndSettle();
    await tester.tap(bar);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(_body(time)).bottom,
      closeTo(_strip(tester).bottom, 0.01),
    );
  });
}
