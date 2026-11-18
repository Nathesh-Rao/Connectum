import 'dart:async';

import 'package:connectum/core/debug/seed_tickets.dart';
import 'package:connectum/data/models/message.dart';
import 'package:connectum/data/models/record_live.dart';
import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/features/tickets/models/card_menu.dart';
import 'package:connectum/features/tickets/widgets/record_menu_rows.dart';
import 'package:connectum/features/tickets/widgets/record_status_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import '../support/fake_socket.dart';
import 'ticket_fixtures.dart';

List<String> _ids(List<CardMenuItem> items) => [for (final i in items) i.id];

RecordState _state({bool isSendOn = true, bool isStatusOn = false}) =>
    RecordState(
      items: [
        RecordActionItem(
          id: 'send',
          label: 'Send',
          isEnabled: isSendOn,
          why: isSendOn ? '' : 'Only the person it is with can do this.',
        ),
        RecordActionItem(
          id: 'status',
          label: 'Update status',
          isEnabled: isStatusOn,
          why: isStatusOn
              ? ''
              : 'This record is Done; only an administrator can change it.',
        ),
      ],
      holder: 'ana',
      initiator: 'ben',
      status: 'Open',
    );

Map<String, dynamic> _event(String name, Map<String, dynamic> data) => {
  'type': 'sd_event',
  'event': name,
  'data': data,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the card menu: the web\'s items, order and conditions', () {
    test('my own settled record card in a direct chat or group', () {
      final items = CardMenu.build(
        canReply: true,
        canCopy: true,
        isMarkable: true,
        isPinnable: true,
        isMine: true,
        record: _state(),
        canEdit: true,
        canOpenHistory: true,
        canDelete: true,
      );
      expect(_ids(items), [
        'reply',
        'copy',
        'save',
        'pin',
        'act-send',
        'act-status',
        'edit',
        'history',
        'delete',
      ]);
      expect(items.firstWhere((i) => i.id == 'delete').isDanger, isTrue);
    });

    test('a card from someone else: Mark as unread, no Edit or Delete', () {
      final items = CardMenu.build(
        canReply: true,
        canCopy: true,
        isMarkable: true,
        isPinnable: true,
        record: _state(),
      );
      expect(_ids(items), [
        'reply',
        'copy',
        'save',
        'pin',
        'unread',
        'act-send',
        'act-status',
      ]);
    });

    test('the general room has no Pin; a team chat has none of the marks', () {
      final global = CardMenu.build(canCopy: true, isMarkable: true);
      expect(_ids(global), ['copy', 'save', 'unread']);
      final team = CardMenu.build(canCopy: true);
      expect(_ids(team), ['copy']);
    });

    test('a form or record card has no Forward row, whatever else is on', () {
      final items = CardMenu.build(
        canReply: true,
        canCopy: true,
        isMarkable: true,
        isPinnable: true,
        record: _state(),
        canEdit: true,
        canOpenHistory: true,
        canDelete: true,
      );
      expect(_ids(items), isNot(contains('forward')));
    });

    test('Save, Pin and Mark as unread are the coming-soon rows', () {
      final items = CardMenu.build(isMarkable: true, isPinnable: true);
      expect(items.every((i) => i.isSoon), isTrue);
      expect(items.length, 3);
    });

    test('a record action that is off keeps the server\'s reason', () {
      final items = CardMenu.build(record: _state(isSendOn: false));
      final send = items.firstWhere((i) => i.id == 'act-send');
      expect(send.isEnabled, isFalse);
      expect(send.why, 'Only the person it is with can do this.');
      final status = items.firstWhere((i) => i.id == 'act-status');
      expect(status.why, contains('only an administrator'));
    });

    test('the menu follows what record.actions offers (no guessing)', () {
      expect(_ids(CardMenu.build(record: null)), isEmpty);
      expect(
        _ids(CardMenu.build(record: const RecordState(items: []))),
        isEmpty,
      );
      final sendOnly = CardMenu.build(
        record: const RecordState(
          items: [RecordActionItem(id: 'send', label: 'Send')],
        ),
      );
      expect(_ids(sendOnly), ['act-send']);
    });

    test('Fix and send again replaces Edit for a declined card', () {
      final fix = CardMenu.build(canEdit: true, isFix: true);
      expect(fix.single.label, 'Fix and send again');
      final edit = CardMenu.build(canEdit: true);
      expect(edit.single.label, 'Edit');
    });

    test('a divider opens each group once, never two in a row', () {
      final items = CardMenu.build(
        canReply: true,
        isMarkable: true,
        record: _state(),
        canEdit: true,
        canDelete: true,
      );
      final dividers = [
        for (final i in items)
          if (i.hasDividerBefore) i.id,
      ];
      expect(dividers, ['save', 'act-send', 'delete']);
      // No record actions: the card's own rows open their group instead.
      final bare = CardMenu.build(canReply: true, canEdit: true);
      expect(bare.last.hasDividerBefore, isTrue);
    });

    test('a record\'s history row has no record to act on', () {
      final items = CardMenu.build(canCopy: true);
      expect(items.any((i) => i.isRecordAction), isFalse);
    });
  });

  group('the menu list', () {
    late FakeSocket socket;
    late TicketRepository repo;

    setUp(() {
      socket = FakeSocket()..goOnline();
      repo = TicketRepository(
        socket,
        FakeStore(user: 'ana'),
        FakeConversations(),
      )..onInit();
      addTearDown(repo.onClose);
      socket.answers[RecordCmd.actions] = fixtureData('record_actions');
    });

    testWidgets('a row that is off shows why and does nothing; others pick', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordMenuRows(
              tickets: repo,
              recordId: null,
              itemsFor: (_) => CardMenu.build(record: _state(isSendOn: false)),
              onPick: (i) => picked.add(i.id),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Send'));
      await tester.pump();
      expect(picked, isEmpty);
      expect(
        find.text('Only the person it is with can do this.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Update status'), warnIfMissed: false);
      expect(picked, isEmpty);
    });

    testWidgets('an enabled row is handed to onPick', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordMenuRows(
              tickets: repo,
              recordId: null,
              itemsFor: (_) => CardMenu.build(
                record: _state(isStatusOn: true),
                isMarkable: true,
              ),
              onPick: (i) => picked.add(i.id),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Update status'));
      await tester.tap(find.text('Save this message'));
      expect(picked, ['act-status', 'save']);
    });

    testWidgets('the record rows read once when the menu opens, not before', (
      tester,
    ) async {
      Widget menu() => MaterialApp(
        home: Scaffold(
          body: RecordMenuRows(
            tickets: repo,
            recordId: 24,
            itemsFor: (state) => CardMenu.build(record: state, canCopy: true),
            onPick: (_) {},
          ),
        ),
      );
      await tester.pumpWidget(menu());
      await tester.pump();
      expect(socket.calls, isEmpty);
      expect(find.text('Send'), findsNothing);
      // The sheet opens: the read starts first, then the list is drawn.
      final release = Completer<void>();
      socket.held[RecordCmd.actions] = release.future;
      final read = repo.ensureMenu(24);
      await tester.pumpWidget(menu());
      expect(find.text('Loading…'), findsOneWidget);
      release.complete();
      await read;
      await tester.pump();
      expect(socket.count(RecordCmd.actions), 1);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Update status'), findsOneWidget);
    });
  });

  group('the live card', () {
    late FakeSocket socket;
    late TicketRepository repo;

    setUp(() {
      socket = FakeSocket()..goOnline();
      repo = TicketRepository(
        socket,
        FakeStore(user: 'ana'),
        FakeConversations(),
      )..onInit();
      addTearDown(repo.onClose);
      socket.answers[RecordCmd.actions] = fixtureData('record_actions');
    });

    test('a record.actions read fills status, holder and the rest', () async {
      await repo.actions(24);
      final live = repo.liveOf(24).value;
      expect(live.status, 'Open');
      expect(live.holder, 'ana');
      expect(live.isStale, isFalse);
      expect(live.isKnown, isTrue);
    });

    test(
      'a records.mine page fills the cards without a read of their own',
      () async {
        socket.answers[RecordCmd.mine] = fixtureData('records_mine_with');
        final page = await repo.mine(as: 'with');
        expect(page.tickets, isNotEmpty);
        final id = page.tickets.first.id;
        final live = repo.liveOf(id).value;
        expect(live.isKnown, isTrue);
        expect(live.holder, page.tickets.first.holder);
        expect(socket.count(RecordCmd.actions), 0);
      },
    );

    test(
      'ticket_assigned: the record is with me now, one card, no command',
      () async {
        await repo.actions(24);
        socket.calls.clear();
        final other = repo.liveOf(25).value;
        repo.onEvent(
          _event('ticket_assigned', {
            'id': 24,
            'tstruct': 'help_ticket',
            'action': 'Send',
            'by': 'ben',
          }),
        );
        final live = repo.liveOf(24).value;
        expect(live.holder, 'ana');
        expect(live.isStale, isTrue);
        expect(live.lastAction, 'Send');
        expect(identical(repo.liveOf(25).value, other), isTrue);
        expect(socket.calls, isEmpty);
      },
    );

    test(
      'submissions_changed: marks that record stale and says what happened',
      () async {
        await repo.actions(24);
        await repo.actions(25);
        repo.onEvent(
          _event('submissions_changed', {
            'id': 24,
            'tstruct': 'help_ticket',
            'action': 'Status update',
          }),
        );
        expect(repo.liveOf(24).value.isStale, isTrue);
        expect(repo.liveOf(24).value.lastAction, 'Status update');
        // What was known stays on the card.
        expect(repo.liveOf(24).value.status, 'Open');
        expect(repo.liveOf(25).value.isStale, isFalse);
        expect(repo.itemsOf(24), isEmpty);
        expect(repo.itemsOf(25), isNotEmpty);
      },
    );

    test('my own status update patches the card at once', () async {
      socket.answers[RecordCmd.mine] = fixtureData('records_mine_with');
      final id = (await repo.mine(as: 'with')).tickets.first.id;
      final patched = repo.applied(
        id,
        RecordPatch.parse({
          'id': id,
          'holder': 'ana',
          'status': 'In progress',
          'completion': 40,
          'final': false,
        }),
      );
      expect(patched, isNotNull);
      final live = repo.liveOf(id).value;
      expect(live.status, 'In progress');
      expect(live.completion, 40);
      expect(live.lastBy, 'ana');
      expect(live.isStale, isFalse);
    });

    test(
      '20 events without a record: one batched summary, one refresh',
      () async {
        await repo.actions(24);
        socket.calls.clear();
        var refreshes = 0;
        final sub = repo.refreshes.listen((_) => refreshes++);
        addTearDown(sub.cancel);
        for (var i = 0; i < 20; i++) {
          repo.onEvent(
            _event('submissions_changed', {
              'id': 24 + (i % 4),
              'tstruct': 'help_ticket',
              'action': 'Status update',
            }),
          );
        }
        await Future<void>.delayed(TicketRepository.burst * 2);
        final sent = socket.calls.where((c) => c.action == RecordCmd.summary);
        expect(sent.length, 1);
        expect(socket.calls.length, 1);
        expect((sent.single.args['ids'] as List).toSet(), {24, 25, 26, 27});
        expect(refreshes, 1);
      },
    );

    test('form_message_updated changes no record and sends nothing', () async {
      await repo.actions(24);
      socket.calls.clear();
      repo.onEvent(
        _event('form_message_updated', {
          'conversation': 'dm:ben',
          'id': 7,
          'form': {'submissionId': 24},
        }),
      );
      expect(repo.liveOf(24).value.isStale, isFalse);
      expect(socket.calls, isEmpty);
    });

    test(
      'a reconnect marks every known card stale (events were lost)',
      () async {
        await repo.actions(24);
        await repo.actions(25);
        repo.invalidate();
        expect(repo.liveOf(24).value.isStale, isTrue);
        expect(repo.liveOf(25).value.isStale, isTrue);
        expect(repo.liveOf(24).value.status, 'Open');
      },
    );

    testWidgets('only the card of the changed record rebuilds', (tester) async {
      await tester.runAsync(() async {
        await repo.actions(24);
        await repo.actions(25);
      });
      var builds24 = 0;
      var builds25 = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Obx(() {
                builds24++;
                return RecordStatusBlock(live: repo.liveOf(24).value);
              }),
              Obx(() {
                builds25++;
                return RecordStatusBlock(live: repo.liveOf(25).value);
              }),
            ],
          ),
        ),
      );
      final b24 = builds24;
      final b25 = builds25;
      repo.onEvent(
        _event('ticket_assigned', {
          'id': 24,
          'tstruct': 't',
          'action': 'Send',
          'by': 'ben',
        }),
      );
      await tester.pump();
      expect(builds24, b24 + 1);
      expect(builds25, b25);
      await tester.pump(TicketRepository.burst * 2);
      // Drawing and scrolling made no command.
      expect(socket.count(RecordCmd.actions), 2);
      expect(repo.cardReads, 0);
    });
  });

  group('the status block of a card (the web\'s RecordStatus)', () {
    Future<void> show(WidgetTester tester, RecordLive live) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecordStatusBlock(
                live: live,
                now: DateTime(2026, 11, 16, 12),
              ),
            ),
          ),
        );

    testWidgets('status chip, who it is with, completion, last update', (
      tester,
    ) async {
      final at = DateTime(2026, 11, 16, 9, 5).millisecondsSinceEpoch;
      await show(
        tester,
        RecordLive(
          status: 'In progress',
          holder: 'sam',
          initiator: 'ana',
          completion: 40,
          lastBy: 'sam',
          lastTs: at,
          lastRemarks: 'Looking at it now.',
          isKnown: true,
        ),
      );
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('With @sam'), findsOneWidget);
      expect(find.text('40%'), findsOneWidget);
      expect(find.text('@sam'), findsOneWidget);
      expect(find.text('9:05 AM'), findsOneWidget);
      expect(find.text('Looking at it now.'), findsOneWidget);
    });

    testWidgets('shared with several people', (tester) async {
      await show(
        tester,
        const RecordLive(
          status: 'Open',
          holder: 'ana',
          initiator: 'ana',
          claimants: ['sam', 'rhea'],
          isKnown: true,
        ),
      );
      expect(find.text('Shared with @sam, @rhea'), findsOneWidget);
    });

    testWidgets('nothing for a record never sent and without a status', (
      tester,
    ) async {
      await show(
        tester,
        const RecordLive(holder: 'ana', initiator: 'ana', isKnown: true),
      );
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('an unknown record shows a neutral dash, never "No status"', (
      tester,
    ) async {
      await show(tester, const RecordLive());
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('No status'), findsNothing);
    });

    testWidgets('a message that only has a state from history shows it', (
      tester,
    ) async {
      final live = RecordLive.fromState(
        const RecordState(
          items: [],
          status: 'Done',
          holder: 'ben',
          initiator: 'ben',
          finalStatuses: ['Done'],
          completion: 100,
        ),
      );
      await show(tester, live);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(live.isFinal, isTrue);
    });
  });

  group('the demo server emits the events a real one does', () {
    final events = <Map<String, dynamic>>[];

    setUp(() async {
      events.clear();
      await SeedTickets.start();
      SeedTickets.emit = events.add;
      addTearDown(() {
        SeedTickets.emit = null;
        SeedTickets.stop();
      });
    });

    test('my status update: submissions_changed with the action', () {
      SeedTickets.answer(RecordCmd.status, {
        'id': 32,
        'status': 'Done',
        'percent': 100,
        'requestId': 'r1',
      });
      expect(events, hasLength(1));
      expect(events.single['event'], 'submissions_changed');
      expect(events.single['data']['id'], 32);
      expect(events.single['data']['action'], 'Status update');
    });

    test('the other person moves a record that is with me', () {
      SeedTickets.otherUpdatesStatus();
      expect(events.single['event'], 'submissions_changed');
      expect(events.single['data']['id'], 31);
      final next = SeedTickets.answer(RecordCmd.actions, {'id': 31});
      expect(next['status'], isNot('Open'));
    });

    test('the other person sends me a record: ticket_assigned first', () {
      final id = SeedTickets.otherSendsRecord();
      expect(events.map((e) => e['event']), [
        'ticket_assigned',
        'submissions_changed',
      ]);
      expect(events.first['data']['by'], 'rhea');
      expect(events.first['data']['id'], id);
    });
  });

  group('a server-posted card among encrypted messages', () {
    test('a plain form message is never "decrypting" or unreadable', () {
      const encrypted = Message(
        msgId: '1',
        convId: 'dm:ben',
        sender: 'ben',
        isMine: false,
        text: 'e2e1:abc',
        ts: 1,
        status: MessageStatus.read,
        isEncrypted: true,
        decryptState: 'ok',
      );
      const card = Message(
        msgId: '2',
        convId: 'dm:ben',
        sender: 'ben',
        isMine: false,
        text: 'Leave Request #7',
        ts: 2,
        status: MessageStatus.read,
        kind: 'form',
        formJson: '{"structure":"leave","submissionId":7,"fields":[]}',
      );
      expect(card.isDecrypting, isFalse);
      expect(card.isEncryptedUnsupported, isFalse);
      expect(encrypted.isEncryptedUnsupported, isFalse);
    });
  });
}
