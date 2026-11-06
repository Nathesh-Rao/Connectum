import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_icons.dart';
import 'package:connectum/core/widgets/app_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final items = [
    AppNavItem(
      label: 'Chats',
      selectedAsset: AppIcons.bottomNav.chatSelected,
      unselectedAsset: AppIcons.bottomNav.chatUnselected,
      showDot: true,
    ),
    AppNavItem(
      label: 'Agents',
      selectedAsset: AppIcons.bottomNav.aiSelected,
      unselectedAsset: AppIcons.bottomNav.aiUnselected,
    ),
    AppNavItem(
      label: 'Submits',
      selectedAsset: AppIcons.bottomNav.submissionsSelected,
      unselectedAsset: AppIcons.bottomNav.submissionsUnselected,
    ),
    AppNavItem(
      label: 'Profile',
      selectedAsset: AppIcons.bottomNav.profileSelected,
      unselectedAsset: AppIcons.bottomNav.profileUnselected,
    ),
  ];

  Widget host(int index, ValueChanged<int> onSelected) => MaterialApp(
    home: Scaffold(
      bottomNavigationBar: AppBottomNav(
        items: items,
        index: index,
        onSelected: onSelected,
      ),
    ),
  );

  Set<String> assets(WidgetTester tester) => tester
      .widgetList<Image>(find.byType(Image))
      .map(
        (i) => ((i.image as ResizeImage).imageProvider as AssetImage).assetName,
      )
      .toSet();

  testWidgets('shows the four labels and the selected icon of the active tab', (
    tester,
  ) async {
    await tester.pumpWidget(host(0, (_) {}));
    await tester.pumpAndSettle();
    for (final l in ['Chats', 'Agents', 'Submits', 'Profile']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(assets(tester), {
      AppIcons.bottomNav.chatSelected,
      AppIcons.bottomNav.aiUnselected,
      AppIcons.bottomNav.submissionsUnselected,
      AppIcons.bottomNav.profileUnselected,
    });
  });

  testWidgets('selecting another tab swaps the icons, items are 48 wide+', (
    tester,
  ) async {
    var index = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) =>
            host(index, (i) => setState(() => index = i)),
      ),
    );
    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(index, 1);
    expect(assets(tester), contains(AppIcons.bottomNav.aiSelected));
    expect(assets(tester), contains(AppIcons.bottomNav.chatUnselected));
    expect(assets(tester), isNot(contains(AppIcons.bottomNav.chatSelected)));
    expect(tester.getSize(find.byType(AppBottomNav)).height, greaterThan(48));
  });

  testWidgets('the selected item has no tint behind it', (tester) async {
    await tester.pumpWidget(host(0, (_) {}));
    await tester.pumpAndSettle();
    final tinted = find.descendant(
      of: find.byType(AppBottomNav),
      matching: find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.color == AppColors.accentTint;
      }),
    );
    expect(tinted, findsNothing);
  });
}
