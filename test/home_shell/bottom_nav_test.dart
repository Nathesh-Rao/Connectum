import 'package:connectum/core/routes/app_pages.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/widgets/app_bottom_nav.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:connectum/features/home_shell/home_shell_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the bar has Smart view and Inbox, and no Profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AppBottomNav(
            index: 3,
            onSelected: (_) {},
            items: HomeShellView.navItems(),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('Smart view'), findsOneWidget);
    expect(find.bySemanticsLabel('Inbox'), findsOneWidget);
    expect(find.bySemanticsLabel('Profile'), findsNothing);
    final labels = HomeShellView.navItems().map((i) => i.label).toList();
    expect(labels, ['Chats', 'Smart view', 'Inbox', 'Agents', 'Submits']);
  });

  test('HomeTab names the order, the routes and the bar items', () {
    expect(HomeTab.values, [
      HomeTab.chats,
      HomeTab.smartView,
      HomeTab.inbox,
      HomeTab.agents,
      HomeTab.submits,
    ]);
    expect(HomeShellController.tabRoutes, [
      AppRoutes.chats,
      AppRoutes.smartView,
      AppRoutes.inbox,
      AppRoutes.aiAgents,
      AppRoutes.submissions,
    ]);
    expect(HomeTab.ofRoute(AppRoutes.submissions), HomeTab.submits);
    expect(HomeTab.ofRoute(AppRoutes.profile), isNull);
    final labels = HomeShellView.navItems().map((i) => i.label).toList();
    expect(labels[HomeTab.submits.index], 'Submits');
    expect(labels[HomeTab.smartView.index], 'Smart view');
  });

  test('Profile is a pushed route, not a tab', () {
    expect(HomeShellController.tabRoutes, isNot(contains(AppRoutes.profile)));
    expect(
      HomeShellController.tabRoutes.length,
      HomeShellView.navItems().length,
    );
    expect(
      AppPages.pages.where((p) => p.name == AppRoutes.profile),
      hasLength(1),
    );
  });
}
