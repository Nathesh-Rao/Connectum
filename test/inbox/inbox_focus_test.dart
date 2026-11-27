import 'package:connectum/core/widgets/app_notices.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/inbox_view.dart';
import 'package:connectum/features/inbox/widgets/inbox_card.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

const _fileId = 'aaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> cardReply(int id) => {
  'submissions': [
    record(
      id,
      values: {
        'title': 'Leave for $id',
        'attach': [_fileId],
      },
      files: {
        'attach': [
          {'id': _fileId, 'name': 'Q.pdf', 'size': 2048, 'ext': 'pdf'},
        ],
      },
    ),
  ],
  'structures': structures,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InboxRig newRig({Route? card}) {
    final rig = InboxRig();
    addTearDown(rig.dispose);
    rig.routes['records.query'] = (_) => queryReply([record(1), record(2)]);
    rig.routes['record.card'] = card ?? (args) => cardReply(args['id'] as int);
    return rig;
  }

  group('the controller', () {
    test(
      'a request from the shell reads record.card and holds the one card',
      () async {
        final rig = newRig();
        final c = rig.controller..onInit();
        await settle();
        rig.shell.recordRequest.value = 42;
        await settle();
        expect(rig.argsOf('record.card'), [
          {'id': 42, 'fileMeta': 2},
        ]);
        expect(c.isFocused, isTrue);
        expect(c.focusId.value, 42);
        expect(c.focusRow.value?.id, 42);
        expect(c.focusRow.value?.files['attach'], isA<List>());
        expect(rig.shell.recordRequest.value, isNull, reason: 'taken once');
        expect(c.isApprovalsOpen, isFalse);
      },
    );

    test('it opens on the Records tab even from the Approvals tab', () async {
      final rig = newRig();
      final c = rig.controller..onInit();
      await settle();
      c.openApprovals();
      rig.shell.recordRequest.value = 7;
      await settle();
      expect(c.isApprovalsOpen, isFalse);
      expect(c.isFocused, isTrue);
    });

    test(
      'Show all records returns to the usual list and the saved view',
      () async {
        final rig = newRig();
        rig.routes['inbox.views.get'] = (_) => {
          'views': [
            {
              'name': 'Default View',
              'view': {
                'folder': 'requests',
                'sort': 'oldest',
                'filters': {
                  'forms': ['t'],
                },
              },
              'savedTs': 1,
            },
          ],
          'default': null,
        };
        final c = rig.controller..onInit();
        await settle();
        final wheres = c.filter.value.wheres;
        expect(wheres, ['requests']);
        c.openRecord(5);
        await settle();
        expect(c.isFocused, isTrue);
        c.showAllRecords();
        expect(c.isFocused, isFalse);
        expect(c.focusRow.value, isNull);
        expect(c.filter.value.wheres, wheres);
        expect(c.views.current.value, '');
      },
    );

    test(
      'a refusal keeps the usual screen and shows the server\'s words',
      () async {
        for (final words in ['I cannot view it.', 'No such submission.']) {
          final rig = newRig(
            card: (_) => throw SocketCallError('forbidden', words),
          );
          final c = rig.controller..onInit();
          await settle();
          await c.openRecord(9);
          expect(c.isFocused, isFalse, reason: words);
          expect(c.focusRow.value, isNull);
          expect(c.page.value, isNotNull, reason: 'the list stays');
          expect(rig.ids, [2, 1]);
        }
      },
    );

    test('an answer with no record is "No such submission."', () async {
      final rig = newRig(
        card: (_) => {'submissions': <dynamic>[], 'structures': structures},
      );
      final c = rig.controller..onInit();
      await settle();
      await c.openRecord(9);
      expect(c.isFocused, isFalse);
    });

    test('a bad id never reads and never crashes', () async {
      final rig = newRig();
      final c = rig.controller..onInit();
      await settle();
      await c.openRecord(0);
      await c.openRecord(-4);
      expect(rig.argsOf('record.card'), isEmpty);
      expect(c.isFocused, isFalse);
      // A garbled answer is a failed read, not a crash.
      rig.routes['record.card'] = (_) => throw const FormatException('x');
      await c.openRecord(3);
      expect(c.isFocused, isFalse);
    });

    test('a newer request wins over an older answer that lands late', () async {
      final rig = newRig();
      final c = rig.controller..onInit();
      await settle();
      rig.socket.handler = null;
      rig.socket.waiting.clear();
      final first = c.openRecord(10);
      await settle();
      final older = rig.socket.waiting.last;
      final second = c.openRecord(11);
      await settle();
      older.done.complete(cardReply(10));
      await first;
      expect(c.focusRow.value, isNull);
      await settle();
      rig.socket.waiting.last.done.complete(cardReply(11));
      await second;
      expect(c.focusRow.value?.id, 11);
    });

    test(
      'a cold start: the request is already there when the Inbox builds',
      () async {
        final rig = newRig();
        rig.shell.recordRequest.value = 33;
        final c = rig.controller..onInit();
        await settle();
        expect(c.focusRow.value?.id, 33);
        expect(rig.shell.recordRequest.value, isNull);
      },
    );

    test('a view or filter change leaves the shown record', () async {
      final rig = newRig();
      final c = rig.controller..onInit();
      await settle();
      await c.openRecord(5);
      expect(c.isFocused, isTrue);
      c.selectScope(InboxScope.me);
      c.applyFilter(c.filter.value.copyWith(sort: 'oldest'));
      await settle();
      expect(c.isFocused, isFalse);
    });

    test('a new session forgets it', () async {
      final rig = newRig();
      final c = rig.controller..onInit();
      await settle();
      await c.openRecord(5);
      rig.store.switchTo('zed');
      await settle();
      expect(c.isFocused, isFalse);
    });
  });

  group('the screen', () {
    Future<InboxRig> pump(
      WidgetTester t, {
      double width = 390,
      double scale = 1,
      Route? card,
    }) async {
      final rig = newRig(card: card);
      Get.put(rig.controller);
      addTearDown(Get.reset);
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: AppNoticeHost(child: child!),
          ),
          home: const InboxView(),
        ),
      );
      await t.runAsync(settle);
      await t.pump(const Duration(milliseconds: 600));
      return rig;
    }

    testWidgets('the strip says Submission #N and Show all records, then the '
        'one card', (t) async {
      final rig = await pump(t);
      expect(find.byType(InboxCard), findsNWidgets(2));
      rig.shell.recordRequest.value = 42;
      await t.runAsync(settle);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Submission #42'), findsOneWidget);
      expect(find.text('Show all records'), findsOneWidget);
      expect(find.byType(InboxCard), findsOneWidget);
      expect(find.text('Leave for 42'), findsOneWidget);
      expect(find.text('Q.pdf'), findsOneWidget, reason: 'files like any card');
      await t.tap(find.text('Show all records'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Submission #42'), findsNothing);
      expect(find.byType(InboxCard), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('a refusal shows the server\'s message on the usual screen', (
      t,
    ) async {
      final rig = await pump(
        t,
        card: (_) =>
            throw const SocketCallError('forbidden', 'I cannot view it.'),
      );
      rig.shell.recordRequest.value = 42;
      await t.runAsync(settle);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('I cannot view it.'), findsOneWidget);
      expect(find.text('Submission #42'), findsNothing);
      expect(find.byType(InboxCard), findsNWidgets(2));
    });

    testWidgets('320 px at text scale 1.5: no overflow, both words stay', (
      t,
    ) async {
      final rig = await pump(t, width: 320, scale: 1.5);
      rig.shell.recordRequest.value = 12345678;
      await t.runAsync(settle);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Submission #'), findsOneWidget);
      expect(find.text('Show all records'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the card taps open the record like every card', (t) async {
      final rig = await pump(t);
      rig.shell.recordRequest.value = 42;
      await t.runAsync(settle);
      await t.pump(const Duration(milliseconds: 600));
      expect(rig.controller.focusRow.value, isNotNull);
      expect(find.byType(InboxCard), findsOneWidget);
    });
  });
}
