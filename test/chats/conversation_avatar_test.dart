import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/conversation_avatar.dart';
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

  final _isOnline = false.obs;

  @override
  AppPresenceDot presenceFor(Conversation c) =>
      _isOnline.value ? AppPresenceDot.online : AppPresenceDot.none;
}

Color? _fill(WidgetTester tester) {
  final box = find
      .descendant(of: find.byType(AppAvatar), matching: find.byType(Container))
      .first;
  return (tester.widget<Container>(box).decoration! as BoxDecoration).color;
}

void main() {
  final cases = <String, Conversation>{
    'personal': const Conversation(
      convId: 'dm:ana',
      kind: 'dm',
      title: 'Ana Lopez',
    ),
    'group': const Conversation(
      convId: 'group:design team',
      kind: 'group',
      title: 'Design Team',
    ),
    'ticket': const Conversation(
      convId: 'group:rec-help_ticket-217',
      kind: 'group',
      title: 'Printer is jammed',
    ),
    'thread (care, named)': const Conversation(
      convId: 'group:care-bruno.silva',
      kind: 'group',
      title: 'Bruno Silva',
    ),
    'thread (care, no name yet)': const Conversation(
      convId: 'group:care-bruno.silva',
      kind: 'group',
      title: 'care-bruno.silva',
    ),
    'team': const Conversation(
      convId: 'host:Billing',
      kind: 'host',
      title: 'Billing',
    ),
  };

  for (final e in cases.entries) {
    testWidgets('${e.key}: the header avatar is the list avatar', (
      tester,
    ) async {
      final c = e.value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationTile(
              conversation: c,
              controller: _FakeChats(),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inList = tester.widget<AppAvatar>(find.byType(AppAvatar));
      final listFill = _fill(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationHeader(
              title: c.title,
              status: null,
              avatar: conversationAvatarFor(c),
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inHeader = tester.widget<AppAvatar>(find.byType(AppAvatar));
      expect(inHeader.name, inList.name);
      expect(inHeader.kind, inList.kind);
      expect(inHeader.size, inList.size);
      expect(_fill(tester), listFill);
      expect(listFill, AvatarPalette.fromName(c.title).background);
    });
  }

  test('the kind follows the conversation', () {
    AppAvatarKind kindOf(String id, String kind, String title) =>
        ConversationAvatarSpec.of(
          Conversation(convId: id, kind: kind, title: title),
        ).kind;
    expect(kindOf('dm:a', 'dm', 'A'), AppAvatarKind.person);
    expect(kindOf('group:g', 'group', 'G'), AppAvatarKind.group);
    expect(kindOf('group:rec-ticket-3', 'group', 'T'), AppAvatarKind.ticket);
    expect(kindOf('group:care-ana', 'group', 'Ana'), AppAvatarKind.person);
    expect(kindOf('group:care-ana', 'group', 'care-ana'), AppAvatarKind.group);
  });

  testWidgets('the header presence dot and lock icon stay', (tester) async {
    const c = Conversation(convId: 'dm:ana', kind: 'dm', title: 'Ana');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationHeader(
            title: c.title,
            status: 'Active now',
            avatar: conversationAvatarFor(c, presence: AppPresenceDot.online),
            isEncrypted: true,
            onBack: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<AppAvatar>(find.byType(AppAvatar)).presence,
      AppPresenceDot.online,
    );
    expect(find.byIcon(Icons.lock), findsOneWidget);
    expect(find.text('Active now'), findsOneWidget);
  });

  testWidgets('tapping the avatar or the title opens the info', (tester) async {
    var taps = 0;
    var backs = 0;
    const c = Conversation(convId: 'dm:ana', kind: 'dm', title: 'Ana Lopez');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationHeader(
            title: c.title,
            status: 'Active now',
            avatar: conversationAvatarFor(c),
            onBack: () => backs++,
            onInfoTap: () => taps++,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AppAvatar));
    await tester.tap(find.text('Ana Lopez'));
    await tester.tap(find.text('Active now'));
    expect(taps, 3);
    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(backs, 1);
    expect(taps, 3);
  });
}
