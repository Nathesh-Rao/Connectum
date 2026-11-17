import 'dart:convert';

import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/app_notification_bell.dart';
import 'package:connectum/core/widgets/app_profile_avatar.dart';
import 'package:connectum/core/widgets/avatar_image.dart';
import 'package:connectum/features/chats/widgets/chats_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  final name = 'Acme'.obs;
  final unread = 3.obs;
  final profile = 'Ann Rao'.obs;
  final picture = RxnString();

  Widget header({VoidCallback? onProfile}) => MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.white,
      body: ChatsHeader(
        enterpriseName: () => name.value,
        unread: () => unread.value,
        onSwitchEnterprise: () {},
        onOpenNotifications: () {},
        profileName: () => profile.value,
        profilePicture: () => picture.value,
        onOpenProfile: onProfile ?? () {},
      ),
    ),
  );

  testWidgets('title on the left, the bell, then the profile avatar', (
    tester,
  ) async {
    await tester.pumpWidget(header());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Acme'), findsOneWidget);
    expect(find.byType(AppNotificationBell), findsOneWidget);
    expect(find.byType(AppProfileAvatar), findsOneWidget);
    expect(
      tester.getCenter(find.text('Acme')).dx,
      lessThan(tester.getCenter(find.byType(AppNotificationBell)).dx),
    );
    expect(
      tester.getCenter(find.byType(AppNotificationBell)).dx,
      lessThan(tester.getCenter(find.byType(AppProfileAvatar)).dx),
    );
    expect(tester.getSize(find.byType(AppAvatar)).height, 30);
  });

  testWidgets('without a picture the first letter shows', (tester) async {
    await tester.pumpWidget(header());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await expectLater(
      find.byType(ChatsHeader),
      matchesGoldenFile('goldens/header_avatar_letter.png'),
    );
  });

  testWidgets('with a picture it is drawn over the letter', (tester) async {
    final url = AvatarImages.registerMemory(_png);
    picture.value = url;
    await tester.pumpWidget(header());
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    await expectLater(
      find.byType(ChatsHeader),
      matchesGoldenFile('goldens/header_avatar_picture.png'),
    );
  });

  testWidgets('tapping the avatar opens Profile', (tester) async {
    var opened = 0;
    await tester.pumpWidget(header(onProfile: () => opened++));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(AppProfileAvatar));
    expect(opened, 1);
  });
}
