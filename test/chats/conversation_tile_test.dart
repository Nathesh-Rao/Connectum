import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:connectum/core/utils/relative_time.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/app_unread_badge.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/features/chats/chats_controller.dart';
import 'package:connectum/features/chats/widgets/conversation_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeChats extends Fake implements ChatsController {
  @override
  final minute = DateTime.now().obs;

  @override
  AppPresenceDot presenceFor(Conversation c) => AppPresenceDot.none;
}

final _ts = DateTime.now().millisecondsSinceEpoch;

void main() {
  Widget host(Conversation c) => MaterialApp(
    home: Scaffold(
      body: ConversationTile(
        conversation: c,
        controller: _FakeChats(),
        onTap: () {},
      ),
    ),
  );

  Conversation conv({bool isMuted = false}) => Conversation(
    convId: 'group:billing',
    kind: 'group',
    title: 'Billing Team',
    lastTs: _ts,
    unread: 3,
    isMuted: isMuted,
  );

  testWidgets('unread badge and time use the avatar colour', (tester) async {
    await tester.pumpWidget(host(conv()));
    await tester.pumpAndSettle();
    final tone = AvatarPalette.fromName('Billing Team').foreground;
    final badge = tester.widget<AppUnreadBadge>(find.byType(AppUnreadBadge));
    expect(badge.color, tone);
    final time = tester.widget<Text>(
      find.text(RelativeTime.label(_ts, DateTime.now())),
    );
    expect(time.style!.color, tone);
    expect(time.style!.fontWeight, FontWeight.w600);
  });

  testWidgets('a muted tile stays grey', (tester) async {
    await tester.pumpWidget(host(conv(isMuted: true)));
    await tester.pumpAndSettle();
    final badge = tester.widget<AppUnreadBadge>(find.byType(AppUnreadBadge));
    expect(badge.isMuted, isTrue);
    final time = tester.widget<Text>(
      find.text(RelativeTime.label(_ts, DateTime.now())),
    );
    expect(time.style!.color, AppColors.muted);
  });
}
