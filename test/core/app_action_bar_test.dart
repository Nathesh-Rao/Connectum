import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/core/widgets/app_action_bar.dart';
import 'package:connectum/core/widgets/app_form_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<ActionItem> _items(int n) => [
  for (var i = 0; i < n; i++)
    ActionItem(id: 'a$i', label: 'Action $i', icon: Icons.send_outlined),
];

Widget _host(
  List<ActionItem> items, {
  void Function(ActionItem)? onTap,
  double width = 320,
  double textScale = 1,
  AppActionLayout layout = AppActionLayout.row,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: AppActionBar(
            items: items,
            layout: layout,
            onTap: onTap ?? (_) {},
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('one or two actions: no expander', (tester) async {
    await tester.pumpWidget(_host(_items(2)));
    expect(find.text('Action 0'), findsOneWidget);
    expect(find.text('Action 1'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsNothing);
  });

  testWidgets('nothing to show builds nothing', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('more than two: a chevron bar with no text toggles the rest', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_items(6)));
    final bar = find.byTooltip('More actions');
    expect(bar, findsOneWidget);
    expect(find.textContaining('More'), findsNothing);
    expect(find.descendant(of: bar, matching: find.byType(Text)), findsNothing);
    expect(
      find.descendant(
        of: bar,
        matching: find.byIcon(Icons.keyboard_arrow_down),
      ),
      findsOneWidget,
    );
    expect(find.text('Action 2'), findsNothing);
    await tester.tap(bar);
    await tester.pumpAndSettle();
    expect(find.text('Action 2'), findsOneWidget);
    expect(find.text('Action 5'), findsOneWidget);
    final turns = tester.widget<AnimatedRotation>(
      find.byType(AnimatedRotation),
    );
    expect(turns.turns, 0.5);
    await tester.tap(bar);
    await tester.pumpAndSettle();
    expect(find.text('Action 2'), findsNothing);
  });

  testWidgets('the bar is 40 dp of strip inside a 48 dp tap target', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_items(3)));
    final hit = tester.getSize(find.byTooltip('More actions'));
    expect(hit.height, 48);
    expect(hit.width, 320);
    final strip = tester.getSize(
      find.descendant(
        of: find.byTooltip('More actions'),
        matching: find.byWidgetPredicate(
          (w) => w is Material && w.color == AppColors.cardChip,
        ),
      ),
    );
    expect(strip.height, 40);
  });

  testWidgets('opened, the rest are the same buttons the details screen has', (
    tester,
  ) async {
    final items = [
      const ActionItem(
        id: 'a',
        label: 'Status update',
        icon: Icons.published_with_changes,
      ),
      const ActionItem(
        id: 'b',
        label: 'Complete',
        icon: Icons.check_circle_outline,
        tone: AppTones.green,
      ),
      const ActionItem(
        id: 'c',
        label: 'Return',
        icon: Icons.undo,
        tone: AppTones.violet,
      ),
      const ActionItem(
        id: 'd',
        label: 'Drop',
        icon: Icons.remove_circle_outline,
        tone: AppTones.red,
      ),
      const ActionItem(id: 'e', label: 'Other', icon: Icons.send_outlined),
    ];
    await tester.pumpWidget(_host(items));
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    Material buttonOf(String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );
    final inCard = {
      for (final l in ['Return', 'Drop', 'Other']) l: buttonOf(l).color,
    };
    final cardSize = tester.getSize(find.text('Return'));
    // Two columns, the odd last one on its own row.
    expect(
      tester.getRect(find.text('Return')).top,
      tester.getRect(find.text('Drop')).top,
    );
    expect(
      tester.getRect(find.text('Other')).top,
      greaterThan(tester.getRect(find.text('Return')).top),
    );
    await tester.pumpWidget(_host(items, layout: AppActionLayout.full));
    await tester.pumpAndSettle();
    for (final l in inCard.keys) {
      expect(buttonOf(l).color, inCard[l], reason: l);
    }
    expect(inCard['Return'], AppTones.violet.tint);
    expect(inCard['Drop'], AppTones.red.tint);
    expect(tester.getSize(find.text('Return')), cardSize);
  });

  testWidgets('a tap gives back the action tapped', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(_host(_items(3), onTap: (a) => tapped.add(a.id)));
    await tester.tap(find.text('Action 1'));
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action 2'));
    expect(tapped, ['a1', 'a2']);
  });

  testWidgets('no overflow when narrow, large text and long labels', (
    tester,
  ) async {
    final items = [
      for (var i = 0; i < 6; i++)
        ActionItem(
          id: '$i',
          label: 'A very long action label number $i',
          icon: Icons.undo,
        ),
    ];
    await tester.pumpWidget(_host(items, width: 200, textScale: 2));
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('full layout shows every action', (tester) async {
    await tester.pumpWidget(
      _host(_items(5), layout: AppActionLayout.full, width: 320),
    );
    for (var i = 0; i < 5; i++) {
      expect(find.text('Action $i'), findsOneWidget);
    }
    expect(find.byTooltip('More actions'), findsNothing);
  });

  testWidgets('the card action area is only there when given', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppFormCardActionArea(child: Text('x'))),
      ),
    );
    expect(find.text('x'), findsOneWidget);
  });

  group('primary action style', () {
    Material buttonOf(WidgetTester tester, String label) =>
        tester.widget<Material>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Material))
              .first,
        );

    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
      return (hi + 0.05) / (lo + 0.05);
    }

    testWidgets('soft by default, from the tokens', (tester) async {
      await tester.pumpWidget(_host(_items(2)));
      final m = buttonOf(tester, 'Action 0');
      expect(kSolidPrimaryAction, isFalse);
      expect(m.color, AppTones.primary.tint);
      expect(buttonOf(tester, 'Action 1').color, AppTones.slate.tint);
      final text = tester.widget<Text>(find.text('Action 0'));
      expect(text.style!.color, AppTones.primary.strong);
      expect(text.style!.fontWeight, FontWeight.w600);
      final shape = m.shape! as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.primary.withValues(alpha: 0.35));
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Action 0'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .height,
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('Action 1'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .height,
      );
    });

    test('the label on the tint reads at 4.5:1 or better', () {
      expect(
        contrast(AppTones.primary.strong, AppTones.primary.tint),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('the full layout uses the same style', (tester) async {
      await tester.pumpWidget(_host(_items(3), layout: AppActionLayout.full));
      expect(buttonOf(tester, 'Action 0').color, AppTones.primary.tint);
    });
  });
}
