import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/conversation_avatar.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/features/conversation/models/chat_item.dart';
import 'package:connectum/features/conversation/widgets/message_bubble.dart';
import 'package:connectum/core/utils/mention_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Titles and usernames fed to the palette. Same-hue collisions are on
/// purpose: names with the same first letter, last letter and length.
final vectorNames = <String>[
  'Priya Sharma',
  'priya sharma',
  '  PRIYA SHARMA  ',
  'Arjun',
  'Meera Nair',
  'Rahul',
  'Sana Khan',
  'Tom',
  'a',
  'A',
  'ab',
  '',
  '   ',
  '\t\n',
  'अर्जुन',
  '李雷',
  '😀 party',
  'Éva',
  'éva',
  'ÉVA',
  'İstanbul',
  'Straße',
  'ß',
  'ΣΑΣ',
  'Ǆemal',
  'Zoë Müller',
  'محمد علي',
  'Иван Петров',
  '👨‍👩‍👧 Family',
  '123',
  '#general',
  '  @  ',
  'ticket #12',
  'Ticket #12',
  'rec-ticket-12',
  'care-ana.lopez',
  'Ana Lopez',
  'Global',
  'My Work Space',
  'priya.sharma',
  'Anna',
  'Aida',
  'Alia',
  'Sam',
  'Sim',
  'Sum',
  'Zoë',
  'Zoe',
  'A name that is rather long indeed, longer than any list row will show it, with several words in it',
  'x' * 300,
  'a b',
  '\u0085Zed\u0085',
  '\uFEFFZed',
  '\u200Bzed',
  '\u180Ezed',
  'Zed\u2003Ali',
  'ǅungla',
  'ᾳbc',
  '\u{1F600}',
  '\u{20000}\u{20001}',
];

/// Titles of conversations of every kind, with the conv id the app stores.
final vectorConversations = <(String convId, String kind, String title, String note)>[
  ('dm:priya.sharma', 'dm', 'priya.sharma', 'direct: title is the peer username, lower case'),
  ('dm:arjun', 'dm', 'arjun', 'direct'),
  ('dm:zoë', 'dm', 'zoë', 'direct, non-ASCII username'),
  ('group:Sales Team', 'group', 'Sales Team', 'group'),
  ('group:Engineering', 'group', 'Engineering', 'group'),
  ('group:rec-ticket-12', 'group', 'Ticket #12', 'ticket thread, made title'),
  ('group:rec-ticket-12', 'group', 'Printer on fire', 'ticket thread, renamed by the server'),
  ('group:rec-leave-request-7', 'group', 'Leave Request #7', 'record thread of another structure'),
  ('group:care-ana.lopez', 'group', 'Ana Lopez', 'care thread with the person name'),
  ('group:care-ana.lopez', 'group', 'care-ana.lopez', 'care thread, title equals the group name: group tile'),
  ('group:care-ana.lopez', 'group', '', 'care thread, empty title: group tile, neutral colours'),
  ('host:Support', 'host', 'Support', 'team (host)'),
  ('global', 'global', 'Global', 'everyone room'),
];

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Map<String, Object?> _avatarOf(WidgetTester tester, Finder avatar) {
  final w = tester.widget<AppAvatar>(avatar);
  final container = tester.widget<Container>(
    find.descendant(of: avatar, matching: find.byType(Container)).first,
  );
  final deco = container.decoration! as BoxDecoration;
  final texts = find.descendant(of: avatar, matching: find.byType(Text));
  String? text;
  String? textColor;
  if (texts.evaluate().isNotEmpty) {
    final t = tester.widget<Text>(texts.first);
    text = t.data;
    textColor = t.style?.color == null ? null : hexOf(t.style!.color!);
  }
  return {
    'kind': w.kind?.name,
    'shape': deco.shape == BoxShape.circle ? 'circle' : 'rounded-square',
    'radius': deco.borderRadius == null ? null : 10,
    'background': deco.color == null ? null : hexOf(deco.color!),
    'text': text,
    'textColor': textColor,
  };
}

/// Every output of the avatar and chat-tile colour rules, from the real code.
Future<Map<String, Object?>> buildAvatarVectors(WidgetTester tester) async {
  final names = <Map<String, Object?>>[];
  for (final name in vectorNames) {
    final index = AvatarPalette.indexOf(name);
    final colors = AvatarPalette.fromName(name);
    await tester.pumpWidget(
      _host(AppAvatar(name: name, kind: AppAvatarKind.person, size: 44)),
    );
    final person = _avatarOf(tester, find.byType(AppAvatar));
    await tester.pumpWidget(_host(AppAvatar(name: name, size: 44)));
    final plainError = tester.takeException() != null;
    final plain = _avatarOf(tester, find.byType(AppAvatar));
    await tester.pumpWidget(
      _host(AppAvatar(name: name, kind: AppAvatarKind.group, size: 44)),
    );
    final group = _avatarOf(tester, find.byType(AppAvatar));
    expect(person['background'], hexOf(colors.background), reason: name);
    expect(group['background'], hexOf(colors.background), reason: name);
    names.add({
      'input': name,
      'paletteIndex': index,
      'hue': index < 0 ? null : AvatarPalette.hues[index].name,
      'foreground': hexOf(colors.foreground),
      'background': hexOf(colors.background),
      'contrast': double.parse(
        AvatarPalette.contrast(colors.foreground, colors.background)
            .toStringAsFixed(2),
      ),
      'personLetter': person['text'],
      'personLetterColor': person['textColor'],
      'plainInitials': plain['text'],
      'plainInitialsRenderError': plainError,
      'plainBackground': plain['background'],
      'plainTextColor': plain['textColor'],
      'tileLeadingColor': index < 0
          ? hexOf(AppColors.primaryBright)
          : hexOf(colors.foreground),
    });
  }

  final conversations = <Map<String, Object?>>[];
  for (final (convId, kind, title, note) in vectorConversations) {
    final c = Conversation(convId: convId, kind: kind, title: title);
    final spec = ConversationAvatarSpec.of(c);
    final colors = AvatarPalette.fromName(spec.name);
    final index = AvatarPalette.indexOf(spec.name);
    await tester.pumpWidget(
      _host(conversationAvatarFor(c, size: 44)),
    );
    final drawn = _avatarOf(tester, find.byType(AppAvatar));
    conversations.add({
      'convId': convId,
      'kind': kind,
      'title': title,
      'note': note,
      'avatarKind': spec.kind.name,
      'seedName': spec.name,
      'paletteIndex': index,
      'foreground': hexOf(colors.foreground),
      'background': hexOf(colors.background),
      'drawnShape': drawn['shape'],
      'drawnBackground': drawn['background'],
      'drawnLetter': drawn['text'],
      'icon': switch (spec.kind) {
        AppAvatarKind.ticket => 'assets/icons/home/ticket.png',
        AppAvatarKind.group => 'assets/icons/home/group.png',
        AppAvatarKind.person => null,
      },
    });
  }

  final senders = <Map<String, Object?>>[];
  for (final name in vectorNames.where((n) => n.trim().isNotEmpty)) {
    final message = Message(
      msgId: '1',
      convId: 'group:x',
      sender: name,
      isMine: false,
      text: 'hello there',
      ts: 1700000000000,
      status: MessageStatus.sent,
    );
    await tester.pumpWidget(
      _host(
        MessageBubble(
          item: ChatItem.message(message, showName: true),
          isDirect: false,
          original: null,
          onLongPress: () {},
          onRetry: () {},
          reactions: const [],
          onReact: (_) {},
          attachmentOf: (_) => const SizedBox(),
          people: const MentionPeople(me: 'me'),
          onReviewKey: () {},
        ),
      ),
    );
    final text = tester.widget<Text>(
      find.byWidgetPredicate((w) => w is Text && w.data == name).first,
    );
    senders.add({'sender': name, 'color': hexOf(text.style!.color!)});
  }
  return {
    'names': names,
    'conversations': conversations,
    'senderInk': senders,
  };
}
