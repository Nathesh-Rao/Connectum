import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_spacing.dart';
import 'package:connectum/core/widgets/app_popup_menu.dart';
import 'package:connectum/core/widgets/app_pill_bar.dart';
import 'package:connectum/features/notifications/notification_texts.dart';
import 'package:connectum/features/notifications/notifications_controller.dart';
import 'package:connectum/features/notifications/widgets/notifications_more_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  Future<List<NotificationsMenuItem>> open(
    WidgetTester tester, {
    double textScale = 1,
    Size size = const Size(400, 800),
    RxBool? groups,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <NotificationsMenuItem>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              NotificationsMoreMenu(
                shouldNotifyGroups: groups ?? true.obs,
                isUnreadOnly: false.obs,
                onSelected: picked.add,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip(NotificationTexts.menu));
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('opens with the five rows in order and the switch states', (
    tester,
  ) async {
    await open(tester);
    final ys = [
      for (final t in [
        NotificationTexts.notifyGroups,
        NotificationTexts.unreadOnly,
        NotificationTexts.markAllRead,
        NotificationTexts.markAllResolved,
        NotificationTexts.clearResolved,
      ])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value), [
      true,
      false,
    ]);
    final card = tester.getRect(find.byType(AppPopupMenuCard));
    expect(card.width, AppSpacing.popupMenuMaxWidth);
    expect(card.right, 400 - AppSpacing.popupMenuMargin);
  });

  testWidgets('a switch row reports once and keeps the menu open', (
    tester,
  ) async {
    final groups = true.obs;
    final picked = await open(tester, groups: groups);
    await tester.tap(find.text(NotificationTexts.unreadOnly));
    await tester.pumpAndSettle();
    expect(picked, [NotificationsMenuItem.unreadOnly]);
    expect(find.byType(AppPopupMenuCard), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(picked.last, NotificationsMenuItem.notifyGroups);
    expect(find.byType(AppPopupMenuCard), findsOneWidget);
  });

  testWidgets('an action row closes the menu and reports', (tester) async {
    final picked = await open(tester);
    await tester.tap(find.text(NotificationTexts.markAllRead));
    await tester.pumpAndSettle();
    expect(picked, [NotificationsMenuItem.markAllRead]);
    expect(find.byType(AppPopupMenuCard), findsNothing);
  });

  testWidgets('Clear resolved is the danger colour', (tester) async {
    await open(tester);
    final text = tester.widget<Text>(
      find.text(NotificationTexts.clearResolved),
    );
    expect(text.style!.color, AppColors.error);
    final icon = tester.widget<Icon>(find.byIcon(Icons.delete_sweep_rounded));
    expect(icon.color, AppColors.error);
  });

  testWidgets('a tap outside closes it', (tester) async {
    final picked = await open(tester);
    await tester.tapAt(const Offset(20, 700));
    await tester.pumpAndSettle();
    expect(find.byType(AppPopupMenuCard), findsNothing);
    expect(picked, isEmpty);
  });

  testWidgets('no overflow narrow and at large text', (tester) async {
    await open(tester, size: const Size(320, 640), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text(NotificationTexts.clearResolved), findsOneWidget);
  });

  testWidgets('the filters are the compact pills of the Chats filters', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppPillBar(
              size: AppPillSize.compact,
              pills: [
                for (final label in NotificationsController.chipLabels)
                  AppPill(label: label),
              ],
              selected: selected,
              onSelected: (i) => setState(() => selected = i),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AppPillBar)).height,
      AppSpacing.compactPillHeight,
    );
    await tester.tap(find.text(NotificationTexts.filterHigh));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });
}
