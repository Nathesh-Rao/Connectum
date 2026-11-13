import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectum/core/utils/avatar_palette.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/avatar_image.dart';
import 'package:connectum/core/widgets/conversation_avatar.dart';
import 'package:connectum/data/models/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Color? _background(WidgetTester tester) {
  final box = tester
      .widgetList<Container>(
        find.descendant(
          of: find.byType(AppAvatar),
          matching: find.byType(Container),
        ),
      )
      .first;
  return (box.decoration as BoxDecoration).color;
}

Future<String> _onePixel(WidgetTester tester) async {
  late Uint8List png;
  await tester.runAsync(() async {
    final r = ui.PictureRecorder();
    ui.Canvas(r).drawRect(
      const ui.Rect.fromLTWH(0, 0, 4, 4),
      ui.Paint()..color = const ui.Color(0xFF00AA00),
    );
    final image = await r.endRecording().toImage(4, 4);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  });
  return AvatarImages.registerMemory(png);
}

void main() {
  const name = 'Asha Rao';

  testWidgets('no picture: the letter on the derived colour', (tester) async {
    await tester.pumpWidget(
      _host(const AppAvatar(name: name, kind: AppAvatarKind.person)),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(_background(tester), AvatarPalette.fromName(name).background);
  });

  testWidgets('a picture that is not there yet: the letter still shows', (
    tester,
  ) async {
    final key = await _onePixel(tester);
    await tester.pumpWidget(
      _host(AppAvatar(name: name, kind: AppAvatarKind.person, picture: key)),
    );
    // first frame, before the image has decoded
    expect(find.text('A'), findsOneWidget);
    expect(_background(tester), AvatarPalette.fromName(name).background);
  });

  testWidgets('a picture that loads is drawn round over the letter', (
    tester,
  ) async {
    final key = await _onePixel(tester);
    await tester.pumpWidget(
      _host(AppAvatar(name: name, kind: AppAvatarKind.person, picture: key)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(ClipOval), findsOneWidget);
    expect(_background(tester), AvatarPalette.fromName(name).background);
  });

  testWidgets('a picture that fails: the letter and colour, no error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const AppAvatar(
          name: name,
          kind: AppAvatarKind.person,
          picture: 'asset:assets/debug/avatars/not-there.png',
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
    expect(_background(tester), AvatarPalette.fromName(name).background);
  });

  testWidgets('an unknown memory key is the same as none', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppAvatar(
          name: name,
          kind: AppAvatarKind.person,
          picture: 'memory:99999',
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('a group keeps its icon whatever it is given', (tester) async {
    final key = await _onePixel(tester);
    await tester.pumpWidget(
      _host(AppAvatar(name: 'Design', kind: AppAvatarKind.group, picture: key)),
    );
    expect(find.byType(ClipOval), findsNothing);
  });

  testWidgets('a plain avatar keeps its size and shape with a picture', (
    tester,
  ) async {
    final key = await _onePixel(tester);
    await tester.pumpWidget(
      _host(AppAvatar(name: name, size: 72, isAccent: true, picture: key)),
    );
    expect(tester.getSize(find.byType(AppAvatar)), const Size(72, 72));
  });

  test('the colour derivation does not depend on the picture', () {
    const a = AppAvatar(name: name, kind: AppAvatarKind.person);
    const b = AppAvatar(
      name: name,
      kind: AppAvatarKind.person,
      picture: '/uploads/x.png',
    );
    expect(
      AvatarPalette.fromName(a.name).background,
      AvatarPalette.fromName(b.name).background,
    );
  });

  test('a direct chat passes its picture; a group does not', () {
    const dm = Conversation(
      convId: 'dm:asha',
      kind: 'dm',
      title: name,
      avatar: '/uploads/a.png',
    );
    const group = Conversation(
      convId: 'group:Design',
      kind: 'group',
      title: 'Design',
      avatar: '/uploads/a.png',
    );
    expect(conversationAvatarFor(dm).picture, '/uploads/a.png');
    expect(conversationAvatarFor(group).picture, isNull);
  });

  test('providers: asset, memory, server, none', () {
    expect(AvatarImages.providerFor(null), isNull);
    expect(AvatarImages.providerFor(''), isNull);
    expect(AvatarImages.providerFor('asset:a.png'), isA<AssetImage>());
    final key = AvatarImages.registerMemory(Uint8List(3));
    expect(AvatarImages.providerFor(key), isA<MemoryImage>());
    AvatarImages.cache = null;
    expect(AvatarImages.providerFor('/uploads/x.png'), isNull);
  });
}
