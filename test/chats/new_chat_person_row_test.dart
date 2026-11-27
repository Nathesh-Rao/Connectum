import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/app_tonal_icon_button.dart';
import 'package:connectum/features/chats/models/chat_person.dart';
import 'package:connectum/features/chats/models/person_link.dart';
import 'package:connectum/features/chats/widgets/new_chat_person_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _person = ChatPerson(
  username: 'alex',
  name: 'Alexandria Montgomery-Featherstonehaugh',
  source: 'colleague',
  detail: 'Senior Registered Nurse · Intensive Care',
);

Widget _row(
  PersonLink link, {
  ChatPerson person = _person,
  bool isSending = false,
  VoidCallback? onOpen,
  VoidCallback? onConnect,
  double width = 320,
  double scale = 1.5,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 640),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(
      body: NewChatPersonRow(
        person: person,
        link: link,
        isSending: isSending,
        onOpen: onOpen ?? () {},
        onConnect: onConnect ?? () {},
      ),
    ),
  ),
);

bool _hasDisc(WidgetTester t) => t
    .widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(AppTonalIconButton),
        matching: find.byType(DecoratedBox),
      ),
    )
    .any(
      (d) =>
          d.decoration is BoxDecoration &&
          (d.decoration as BoxDecoration).shape == BoxShape.circle,
    );

void main() {
  setUp(() {});

  for (final link in PersonLink.values) {
    testWidgets('$link row fits 320 px at 1.5x text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_row(link));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('not connected: bare blue icon, tap connects', (t) async {
    var connects = 0;
    await t.pumpWidget(_row(PersonLink.none, onConnect: () => connects++));
    final icon = t.widget<Icon>(find.byIcon(Icons.person_add_outlined));
    expect(icon.color, AppTones.blue.strong);
    expect(_hasDisc(t), isFalse);
    await t.tap(find.byIcon(Icons.person_add_outlined));
    expect(connects, 1);
  });

  testWidgets('pressed: 0.92 scale', (t) async {
    await t.pumpWidget(_row(PersonLink.none, scale: 1));
    final g = await t.startGesture(
      t.getCenter(find.byIcon(Icons.person_add_outlined)),
    );
    await t.pumpAndSettle();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.92);
    await g.up();
    await t.pumpAndSettle();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('requested: dimmed violet hourglass, not tappable', (t) async {
    var taps = 0;
    await t.pumpWidget(
      _row(PersonLink.requested, onConnect: () => taps++, onOpen: () => taps++),
    );
    final icon = t.widget<Icon>(find.byIcon(Icons.hourglass_empty));
    expect(icon.color!.a, closeTo(0.8, 0.01));
    expect(_hasDisc(t), isFalse);
    await t.tap(find.byIcon(Icons.hourglass_empty), warnIfMissed: false);
    expect(taps, 1, reason: 'only the row tap (onOpen) fires, not the icon');
    expect(find.byTooltip('Requested'), findsOneWidget);
    final handle = t.ensureSemantics();
    final node = t.getSemantics(find.byTooltip('Requested'));
    expect(node.label, contains('Requested'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });

  testWidgets('connected: no icon, the row still opens the chat', (t) async {
    var opens = 0;
    await t.pumpWidget(_row(PersonLink.connected, onOpen: () => opens++));
    expect(find.byType(AppTonalIconButton), findsNothing);
    expect(find.byType(Icon), findsNothing);
    await t.tap(find.text(_person.name));
    expect(opens, 1);
  });

  testWidgets('sending: 16 dp progress in the tone, no icon, no tap', (
    t,
  ) async {
    var connects = 0;
    await t.pumpWidget(
      _row(PersonLink.none, isSending: true, onConnect: () => connects++),
    );
    final bar = find.byType(CircularProgressIndicator);
    expect(t.getSize(bar), const Size(16, 16));
    expect(
      t.widget<CircularProgressIndicator>(bar).color,
      AppTones.blue.strong,
    );
    expect(find.byIcon(Icons.person_add_outlined), findsNothing);
    await t.tap(bar, warnIfMissed: false);
    expect(connects, 0);
  });

  testWidgets('icon is 20 dp in a 44 dp tap area', (t) async {
    for (final (link, icon) in [
      (PersonLink.none, Icons.person_add_outlined),
      (PersonLink.requested, Icons.hourglass_empty),
    ]) {
      await t.pumpWidget(_row(link, scale: 1));
      expect(t.getSize(find.byIcon(icon)), const Size(20, 20));
      final tap = find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(SizedBox),
      );
      expect(t.getSize(tap.first), const Size(44, 44));
    }
  });

  testWidgets('avatar without a picture uses the chat list palette', (t) async {
    await t.pumpWidget(_row(PersonLink.none, scale: 1));
    final avatar = t.widget<AppAvatar>(find.byType(AppAvatar));
    expect(avatar.kind, AppAvatarKind.person);
    expect(avatar.picture, isNull);
    final expected = AvatarPalette.fromName(_person.name);
    final text = t.widget<Text>(
      find.descendant(of: find.byType(AppAvatar), matching: find.text('A')),
    );
    expect(text.style?.color, expected.foreground);
    final decorated = t
        .widgetList<Container>(
          find.descendant(
            of: find.byType(AppAvatar),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(decorated.color, expected.background);
  });

  testWidgets('avatar with a picture is handed the address', (t) async {
    await t.pumpWidget(
      _row(
        PersonLink.none,
        scale: 1,
        person: const ChatPerson(
          username: 'alex',
          name: 'Alex',
          source: 'colleague',
          avatar: 'memory:none',
        ),
      ),
    );
    expect(t.widget<AppAvatar>(find.byType(AppAvatar)).picture, 'memory:none');
  });
}
