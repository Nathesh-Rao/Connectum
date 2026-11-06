import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/app_notification_bell.dart';
import 'package:connectum/features/chats/widgets/chats_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void main() {
  final name = 'Acme'.obs;
  final unread = 3.obs;

  testWidgets('title on the left, only the bell on the right, no avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatsHeader(
            enterpriseName: () => name.value,
            unread: () => unread.value,
            onSwitchEnterprise: () {},
            onOpenNotifications: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Acme'), findsOneWidget);
    expect(find.byType(AppNotificationBell), findsOneWidget);
    expect(find.byType(AppAvatar), findsNothing);
    expect(
      tester.getCenter(find.text('Acme')).dx,
      lessThan(tester.getCenter(find.byType(AppNotificationBell)).dx),
    );
  });
}
