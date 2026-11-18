import 'dart:convert';

import 'package:connectum/core/theme/app_colors.dart';
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

  testWidgets('the avatar is 38 dp with a 2 dp violet ring, 12 dp from the '
      'edge and 18 dp from the bell', (tester) async {
    unread.value = 0;
    addTearDown(() => unread.value = 3);
    await tester.pumpWidget(header());
    await tester.pump(const Duration(milliseconds: 300));
    final ring = find.descendant(
      of: find.byType(AppProfileAvatar),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).border != null,
      ),
    );
    expect(tester.getSize(ring), const Size(38, 38));
    final box = (tester.widget<Container>(ring).decoration! as BoxDecoration);
    final side = (box.border! as Border).top;
    expect(side.width, 2);
    expect(side.color, AppColors.violetRing);
    expect(AppColors.violetRing.a, closeTo(0.35, 0.01));
    expect(tester.getSize(find.byType(AppAvatar)), const Size(30, 30));
    final screen =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(screen - tester.getRect(ring).right, 12);
    final bellRight =
        tester.getCenter(find.byType(AppNotificationBell)).dx + 15;
    expect(tester.getRect(ring).left - bellRight, 18);
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

  for (final scale in [1.0, 1.3]) {
    testWidgets('no overflow at 320 dp wide, text x$scale', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      name.value = 'A very long enterprise name that cannot fit here';
      addTearDown(() => name.value = 'Acme');
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(scale),
          ),
          child: header(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byType(AppProfileAvatar)).right,
        lessThan(321),
      );
    });
  }
}
