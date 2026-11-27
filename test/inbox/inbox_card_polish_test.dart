import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectum/core/theme/app_colors.dart';
import 'package:connectum/core/theme/app_tones.dart';
import 'package:connectum/core/utils/avatar_tint.dart';
import 'package:connectum/core/widgets/app_avatar.dart';
import 'package:connectum/core/widgets/avatar_image.dart';
import 'package:connectum/data/attachment_cache.dart';
import 'package:connectum/data/repositories/sv_file_repository.dart';
import 'package:connectum/features/inbox/models/inbox_card_rows.dart';
import 'package:connectum/features/inbox/models/inbox_field_kind.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:connectum/features/inbox/widgets/inbox_avatar_ring.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:connectum/features/inbox/widgets/inbox_card_frame.dart';
import 'package:connectum/features/inbox/widgets/inbox_file_chip.dart';
import 'package:connectum/features/smart_view/widgets/sv_file_preview_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tickets/ticket_fixtures.dart';
import 'inbox_screen_support.dart';

InboxRow rowOf(Map<String, dynamic> raw) =>
    InboxRow.tryParse(raw, InboxForm.parseAll(structures))!;

const _ids = ['aaaaaaaaaaaaaaaaaaaaaaaa', 'bbbbbbbbbbbbbbbbbbbbbbbb'];

Future<Uint8List> _solidPng() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 16, 16),
    ui.Paint()..color = const ui.Color(0xFFE53935),
  );
  final image = await recorder.endRecording().toImage(16, 16);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;

  Future<void> pumpCard(
    WidgetTester tester,
    InboxRow row, {
    double width = 390,
    double scale = 1,
    int settleMs = 400,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: const ValueKey('golden'),
              child: InboxCard(controller: rig.controller, row: row),
            ),
          ),
        ),
      ),
    );
    for (var t = 0; t < settleMs; t += 100) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() {
    rig = InboxRig(
      files: SvFileRepository(
        dio: Dio(),
        token: () => null,
        origin: '',
        cache: AttachmentCache(Dio()),
        onUnauthorized: () {},
      ),
    );
    rig.controller.onInit();
    addTearDown(rig.dispose);
  });

  Finder circle() => find.byKey(const ValueKey('inbox-status-circle'));

  group('trailing area', () {
    testWidgets('no menu: the circle sits at the far right edge', (
      tester,
    ) async {
      await pumpCard(tester, rowOf(record(1)));
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      final card = tester.getRect(find.byType(InboxCardFrame));
      final c = tester.getRect(circle());
      // 16 px of the header's padding and a hairline: no 32 px empty button.
      expect(card.right - c.right, lessThan(20));
    });

    testWidgets('with a menu: the circle sits beside the button', (
      tester,
    ) async {
      rig.routes['record.actions'] = (_) => fixtureData('record_actions');
      await pumpCard(tester, rowOf(record(1)), settleMs: 3000);
      final button = tester.getRect(find.byIcon(Icons.more_horiz));
      final c = tester.getRect(circle());
      expect(c.right, lessThanOrEqualTo(button.left + 1));
      expect(button.left - c.right, lessThan(16));
    });

    testWidgets('the menu opens as a popup under the button and closes', (
      tester,
    ) async {
      rig.routes['record.actions'] = (_) => fixtureData('record_actions');
      await pumpCard(tester, rowOf(record(1)), settleMs: 3000);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Record'), findsNothing, reason: 'no sheet title');
      final button = tester.getRect(find.byIcon(Icons.more_horiz));
      final popup = tester.getRect(find.text('History'));
      expect(popup.top, greaterThan(button.bottom));
      final size = tester.view.physicalSize;
      expect(popup.right, lessThanOrEqualTo(size.width));
      expect(popup.left, greaterThanOrEqualTo(0));
      await tester.tapAt(const Offset(200, 860));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('History'), findsNothing);
    });
  });

  group('header', () {
    testWidgets('person icon with a bold name, bold #id, date and time icons', (
      tester,
    ) async {
      await pumpCard(tester, rowOf(record(573, holder: 'ben')));
      final name = tester.widget<Text>(find.text('ben'));
      expect(name.style!.fontWeight, FontWeight.w700);
      final id = tester.widget<Text>(find.text('#573'));
      expect(id.style!.fontWeight, FontWeight.w700);
      expect(find.byIcon(Icons.person_outline_rounded), findsWidgets);
      expect(find.byIcon(Icons.calendar_today_outlined), findsWidgets);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(id.style!.fontSize, greaterThanOrEqualTo(13));
    });

    testWidgets('the meta wraps at 320 px and text scale 1.5', (tester) async {
      await pumpCard(
        tester,
        rowOf(record(573, holder: 'a.very.long.user.name')),
        width: 320,
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('#573'), findsOneWidget);
    });
  });

  group('rows', () {
    test('the icon follows the type, then the shape, then the name', () {
      InboxFieldKind k(String name, Object? raw, {String? type}) =>
          InboxFieldKind.of(name: name, key: name, raw: raw, type: type);
      expect(k('Anything', 'x', type: 'date'), InboxFieldKind.date);
      expect(k('Anything', 'x', type: 'number'), InboxFieldKind.number);
      expect(k('Anything', _ids), InboxFieldKind.file);
      expect(k('Anything', '2026-11-16'), InboxFieldKind.date);
      expect(k('Anything', 'https://a.b/c'), InboxFieldKind.link);
      expect(k('Assignee', 'ben'), InboxFieldKind.person);
      expect(k('Amount', '12'), InboxFieldKind.number);
      expect(k('Location', 'Block B'), InboxFieldKind.location);
      expect(k('Category', 'IT'), InboxFieldKind.tag);
      expect(k('Description', 'x'), InboxFieldKind.text);
      expect(k('Whatever', '42'), InboxFieldKind.number);
      expect(k('Whatever', '@ben'), InboxFieldKind.person);
      expect(k('Whatever', 'plain'), InboxFieldKind.other);
    });

    test('file ids become files, an ISO date the app date', () {
      final rows = inboxCardRows(
        rowOf(
          record(
            1,
            values: {
              'title': 'x',
              'docs': _ids,
              'one': [_ids.first],
              'due': '2026-11-16',
            },
          ),
        ),
      );
      final docs = rows.firstWhere((r) => r.name == 'docs');
      expect(docs.value, '2 files');
      expect(docs.files.map((f) => f.id), _ids);
      expect(rows.firstWhere((r) => r.name == 'one').value, '1 file');
      final due = rows.firstWhere((r) => r.name == 'due');
      expect(due.value, '16 Nov 2026');
      expect(due.kind, InboxFieldKind.date);
    });

    testWidgets('an icon square per row, a long value wraps, no raw ids', (
      tester,
    ) async {
      final long = List.filled(40, 'word').join(' ');
      await pumpCard(
        tester,
        rowOf(
          record(
            2,
            values: {
              'title': 'x',
              'due': '2026-11-16',
              'description': long,
              'docs': _ids,
            },
          ),
        ),
        width: 320,
      );
      expect(find.byKey(const ValueKey('inbox-row-icon-date')), findsOneWidget);
      expect(find.text('16 Nov 2026'), findsOneWidget);
      expect(find.text(long), findsOneWidget);
      expect(find.text(_ids.first), findsNothing);
      expect(find.text('2 files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the file chip opens the Smart View file preview', (
      tester,
    ) async {
      await pumpCard(
        tester,
        rowOf(record(3, values: {'title': 'x', 'docs': _ids})),
      );
      expect(find.byType(InboxFileChip), findsOneWidget);
      await tester.tap(find.text('2 files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SvFilePreviewHost), findsOneWidget);
    });

    testWidgets('Show more still expands', (tester) async {
      final more = {for (var i = 1; i <= 6; i++) 'f$i': 'value $i'};
      await pumpCard(tester, rowOf(record(4, values: {'title': 't', ...more})));
      expect(find.text('value 6'), findsNothing);
      await tester.tap(find.textContaining('Show more'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('value 6'), findsOneWidget);
    });
  });

  testWidgets('the card has only the top right wash, in its own layer', (
    tester,
  ) async {
    await pumpCard(tester, rowOf(record(5)));
    expect(find.byType(InboxCardWash), findsOneWidget);
    expect(find.byType(InboxAvatarWash), findsNothing);
    for (final w in tester.widgetList<InboxCardWash>(
      find.byType(InboxCardWash),
    )) {
      expect(
        find.descendant(
          of: find.byWidget(w),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );
    }
    expect(AppTones.green.solid, isNotNull);
  });

  group('the record screen wash (InboxAvatarWash)', () {
    testWidgets('a photo gives it the picture\'s colour, faded in, read once', (
      tester,
    ) async {
      AvatarTint.reset();
      addTearDown(AvatarTint.reset);
      final bytes = (await tester.runAsync(_solidPng))!;
      final picture = AvatarImages.registerMemory(bytes);
      Future<void> pumpWash() => tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [InboxAvatarWash(picture: picture)]),
        ),
      );
      await tester.runAsync(() async {
        await pumpWash();
        expect(find.byType(InboxCardWash), findsOneWidget);
        expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          0,
        );
        await AvatarTint.of(picture);
        await tester.pump();
      });
      await tester.pump(const Duration(milliseconds: 600));
      final tint = AvatarTint.peek(picture)!;
      expect(tint.r, greaterThan(tint.b));
      expect(
        tester.widget<InboxCardWash>(find.byType(InboxCardWash)).color,
        tint,
      );
      // Scrolled back in: known, drawn at once, no second read.
      await pumpWash();
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(await AvatarTint.of(picture), tint);
    });

    testWidgets('a picture that cannot be found falls back to the initials '
        'colour', (tester) async {
      AvatarTint.reset();
      addTearDown(AvatarTint.reset);
      const picture = 'memory:no-such-picture';
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Stack(children: [InboxAvatarWash(picture: picture)]),
          ),
        );
        await AvatarTint.of(picture);
        await tester.pump();
      });
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester.widget<InboxCardWash>(find.byType(InboxCardWash)).color,
        AppColors.avatarText,
      );
    });
  });

  group('the avatar ring', () {
    testWidgets('geometry: 2 dp ring, 2 dp surface gap, photo inside', (
      tester,
    ) async {
      await pumpCard(tester, rowOf(record(5)));
      final ring = find.byKey(const ValueKey('inbox-avatar-ring'));
      expect(tester.getSize(ring), const Size(56, 56));
      final box = tester.widget<Container>(ring);
      final deco = box.decoration! as BoxDecoration;
      expect((deco.border! as Border).top.width, 2);
      expect(deco.color, AppColors.white);
      expect(box.padding, const EdgeInsets.all(2));
      expect(
        tester.getSize(
          find.descendant(of: ring, matching: find.byType(AppAvatar)),
        ),
        const Size(48, 48),
      );
    });

    testWidgets('no photo: the initials colour', (tester) async {
      await pumpCard(tester, rowOf(record(5)));
      final deco =
          tester
                  .widget<Container>(
                    find.byKey(const ValueKey('inbox-avatar-ring')),
                  )
                  .decoration!
              as BoxDecoration;
      expect((deco.border! as Border).top.color, AppColors.avatarText);
    });

    testWidgets('a photo: starts on the fallback, animates to the read '
        'colour', (tester) async {
      AvatarTint.reset();
      addTearDown(AvatarTint.reset);
      final bytes = (await tester.runAsync(_solidPng))!;
      final picture = AvatarImages.registerMemory(bytes);
      Color ringColor() =>
          ((tester
                              .widget<Container>(
                                find.byKey(const ValueKey('inbox-avatar-ring')),
                              )
                              .decoration!
                          as BoxDecoration)
                      .border!
                  as Border)
              .top
              .color;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: InboxAvatarRing(name: 'Ann', picture: picture),
          ),
        );
        expect(ringColor(), AppColors.avatarText);
        await AvatarTint.of(picture);
        await tester.pump();
      });
      await tester.pump(const Duration(seconds: 1));
      expect(ringColor(), AvatarTint.peek(picture));
      expect(
        AvatarTint.contrast(ringColor(), AppColors.white),
        greaterThanOrEqualTo(AvatarTint.minContrast),
      );
    });

    testWidgets('header stays aligned at 320 px with 1.5x text', (
      tester,
    ) async {
      await pumpCard(
        tester,
        rowOf(record(5, values: {'title': 'A long title for a record'})),
        width: 320,
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      final ring = tester.getRect(
        find.byKey(const ValueKey('inbox-avatar-ring')),
      );
      final title = tester.getRect(
        find
            .descendant(
              of: find.byType(InboxCardFrame),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(ring.top, closeTo(title.top, 14));
      expect(ring.left, lessThan(title.left));
    });
  });

  group('the status strip', () {
    testWidgets('sits across the bottom, no pill under the header, in both '
        'states', (tester) async {
      final more = {for (var i = 1; i <= 6; i++) 'f$i': 'value $i'};
      await pumpCard(
        tester,
        rowOf(record(6, values: {'title': 't', 'stage': 'Open', ...more})),
      );
      final strip = find.byKey(const ValueKey('inbox-status-strip'));
      final card = find.byType(InboxCardFrame);
      expect(strip, findsOneWidget);
      expect(find.descendant(of: strip, matching: find.text('Open')), findsOne);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.getRect(strip).width, tester.getRect(card).width);
      expect(
        tester.getRect(card).bottom - tester.getRect(strip).bottom,
        lessThanOrEqualTo(2),
      );
      await tester.tap(find.textContaining('Show more'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(strip, findsOneWidget);
      expect(
        tester.getRect(card).bottom - tester.getRect(strip).bottom,
        lessThanOrEqualTo(2),
      );
      expect(find.text('Open'), findsOneWidget);
    });
  });

  testWidgets('golden: a record card', (tester) async {
    rig.routes['people.cards'] = (_) => {'people': <String, dynamic>{}};
    await pumpCard(
      tester,
      rowOf(
        record(
          573,
          holder: 'ben',
          values: {
            'title': 'Laptop request',
            'stage': 'Open',
            'priority': 'High',
            'due': '2026-11-16',
            'docs': _ids,
            'description': 'New laptop for the design team',
          },
        ),
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('golden')),
      matchesGoldenFile('goldens/inbox_card_polish.png'),
    );
  });
}
