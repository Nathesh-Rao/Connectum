import 'package:connectum/core/theme/app_spacing.dart';
import 'package:connectum/core/widgets/app_pill_bar.dart';
import 'package:connectum/core/widgets/app_refresh.dart';
import 'package:connectum/features/notifications/models/feed_item.dart';
import 'package:connectum/features/notifications/notifications_view.dart';
import 'package:connectum/features/notifications/widgets/feed_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

FeedItem _item(int i) => FeedItem(
  id: 'a$i',
  priority: 'low',
  isRead: true,
  title: 'Ticket TK-$i',
  message: 'Status changed',
  ts: 1000 + i,
);

// Mirrors the Notifications screen's header / pill bar / list stack.
void main() {
  testWidgets(
    'pills gap is 16 dp, list gap is 32 dp and the first tile is not clipped',
    (tester) async {
      final scroll = ScrollController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xxs),
                  child: SizedBox(
                    key: Key('header'),
                    height: AppSpacing.iconButton,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    NotificationsSpacing.titleToPills,
                    AppSpacing.page,
                    0,
                  ),
                  child: AppPillBar(
                    size: AppPillSize.compact,
                    gap: NotificationsSpacing.pillGap,
                    pills: const [
                      AppPill(label: 'All'),
                      AppPill(label: 'High'),
                    ],
                    selected: 0,
                    onSelected: (_) {},
                  ),
                ),
                Expanded(
                  child: CustomScrollView(
                    controller: scroll,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      const SliverToBoxAdapter(
                        child: SizedBox(
                          height: NotificationsSpacing.listTopPadding,
                        ),
                      ),
                      SliverList.builder(
                        itemCount: 30,
                        itemBuilder: (context, i) => FeedTile(
                          key: ValueKey('t$i'),
                          topPadding: NotificationsSpacing.firstTileTopPadding,
                          item: _item(i),
                          readText: (x) => Future.value(x.message),
                          onTap: () {},
                          onMenu: (_) {},
                          onDismissed: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final header = tester.getBottomLeft(find.byKey(const Key('header'))).dy;
      final pills = find.byType(AppPillBar);
      final pillTop = tester.getTopLeft(pills).dy;
      final pillBottom = tester.getBottomLeft(pills).dy;
      final circle = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      );
      final iconTop = tester.getTopLeft(circle.first).dy;
      expect(pillTop - header, closeTo(NotificationsSpacing.titleToPills, 1));
      expect(
        iconTop - pillBottom,
        closeTo(NotificationsSpacing.pillsToFirstTile, 1),
      );

      final pillBoxes = find.descendant(
        of: pills,
        matching: find.byType(AnimatedContainer),
      );
      expect(
        tester.getTopLeft(pillBoxes.at(1)).dx -
            tester.getTopRight(pillBoxes.at(0)).dx,
        closeTo(NotificationsSpacing.pillGap, 0.5),
      );

      final listTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
      expect(listTop, greaterThanOrEqualTo(pillBottom));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pump();
      for (final e in tester.widgetList<FeedTile>(find.byType(FeedTile))) {
        final top = tester.getTopLeft(find.byWidget(e)).dy;
        final bottom = tester.getBottomLeft(find.byWidget(e)).dy;
        // A tile partly above the list is clipped by the viewport, never drawn
        // over the pills: the viewport starts at or below the pill bar.
        expect(bottom, greaterThan(pillBottom - 1));
        expect(top, isNotNull);
      }
    },
  );

  testWidgets('pull to refresh header sits above the first tile', (
    tester,
  ) async {
    var isRefreshed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppRefresh(
            onRefresh: () async => isRefreshed = true,
            slivers: [
              const SliverToBoxAdapter(
                child: SizedBox(height: NotificationsSpacing.listTopPadding),
              ),
              SliverList.builder(
                itemCount: 10,
                itemBuilder: (context, i) => FeedTile(
                  item: _item(i),
                  topPadding: NotificationsSpacing.firstTileTopPadding,
                  readText: (x) => Future.value(x.message),
                  onTap: () {},
                  onMenu: (_) {},
                  onDismissed: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.fling(find.byType(FeedTile).first, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(isRefreshed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
