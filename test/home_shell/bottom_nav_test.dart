import 'package:connectum/core/routes/app_pages.dart';
import 'package:connectum/core/routes/app_routes.dart';
import 'package:connectum/core/widgets/app_bottom_nav.dart';
import 'package:connectum/features/home_shell/home_shell_controller.dart';
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
    expect(labels, ['Chats', 'Agents', 'Submits', 'Smart view', 'Inbox']);
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
