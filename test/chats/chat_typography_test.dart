import 'package:connectum/core/theme/app_text.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/app_unread_badge.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/features/chats/chats_controller.dart';
import 'package:connectum/features/chats/widgets/conversation_tile.dart';
import 'package:connectum/features/conversation/widgets/conversation_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _FakeChats extends Fake implements ChatsController {
  @override
  final minute = DateTime.now().obs;

  @override
  AppPresenceDot presenceFor(Conversation c) => AppPresenceDot.none;
}

void main() {
  test('chat text styles keep their size and weight', () {
    void is_(TextStyle s, double size, FontWeight w) {
      expect(s.fontSize, size);
      expect(s.fontWeight, w);
    }

    is_(AppText.chatMessage, 16, FontWeight.w400);
    is_(AppText.chatName, 16, FontWeight.w600);
    is_(AppText.chatPreview, 14, FontWeight.w400);
    is_(AppText.chatHeaderName, 18, FontWeight.w600);
    is_(AppText.chatInput, 16, FontWeight.w400);
    is_(AppText.chatTime, 11, FontWeight.w400);
    is_(AppText.chatStatus, 12, FontWeight.w400);
    is_(AppText.chatUnread, 12, FontWeight.w600);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('chat row and header do not overflow at $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = Conversation(
        convId: 'group:billing',
        kind: 'group',
        title: 'A very long conversation title that has to be cut',
        lastTs: DateTime.now().millisecondsSinceEpoch,
        unread: 120,
        isPinned: true,
        isMuted: true,
        lastText: 'A long last message that should stay on one line',
        lastFrom: 'Someone',
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Column(
              children: [
                ConversationHeader(
                  title: 'A very long conversation title that has to be cut',
                  status: 'online',
                  avatar: const SizedBox(width: 40, height: 40),
                  onBack: () {},
                ),
                ConversationTile(
                  conversation: c,
                  controller: _FakeChats(),
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final badge = tester.getSize(find.byType(AppUnreadBadge));
      expect(badge.height, greaterThanOrEqualTo(19));
    });
  }
}
