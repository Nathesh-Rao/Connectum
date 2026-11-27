import 'dart:io';

import 'package:connectum/data/models/form_card.dart';
import 'package:connectum/data/models/record_state.dart';
import 'package:connectum/data/records/record_actions_queue.dart';
import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/ticket_repository.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/core/widgets/app_form_card.dart';
import 'package:connectum/features/tickets/models/card_menu.dart';
import 'package:connectum/features/tickets/widgets/record_card_actions.dart';
import 'package:flutter/material.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_socket.dart';

Map<String, dynamic> _reply(List<Object?> items) => {
  'items': items,
  'holder': 'ana',
  'initiator': 'rhea',
  'status': 'Open',
  'statuses': ['Open', 'Done'],
  'final': ['Done'],
};

Map<String, Object?> _item(String id, {bool enabled = true, String? why}) => {
  'id': id,
  'label': id == 'send' ? 'Send' : 'Update status',
  'enabled': enabled,
  'why': ?why,
};

FormCardData _card(int id) => FormCardData(
  id: '$id',
  caption: 'Help ticket',
  structure: 'help_ticket',
  scope: 'user',
  by: 'rhea',
  ts: 1,
  entries: const [],
);

/// The fake clock the repository and the queue read; [run] moves it with the
/// pumped time.
var _clock = DateTime(2026, 1, 1);

/// Pumps [d] of fake time in small steps.
Future<void> run(WidgetTester t, Duration d) async {
  for (var left = d; left > Duration.zero;) {
    const step = Duration(milliseconds: 50);
    final s = left < step ? left : step;
    await t.pump(s);
    _clock = _clock.add(s);
    left -= s;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'filtering truth table (only what the server returned and enabled)',
    () {
      List<String> offered(Map<String, dynamic> data) =>
          RecordState.parse(data).offered.map((i) => i.id).toList();

      test('both', () {
        expect(offered(_reply([_item('send'), _item('status')])), [
          'send',
          'status',
        ]);
      });
      test('send absent: never added', () {
        expect(offered(_reply([_item('status')])), ['status']);
        expect(RecordState.parse(_reply([_item('status')])).hasSend, isFalse);
      });
      test('status absent: never added', () {
        expect(offered(_reply([_item('send')])), ['send']);
        expect(RecordState.parse(_reply([_item('send')])).hasStatus, isFalse);
      });
      test(
        'a disabled item is not offered, but stays for the menu with why',
        () {
          final s = RecordState.parse(
            _reply([
              _item('send', enabled: false, why: 'Not now'),
              _item('status'),
            ]),
          );
          expect(s.offered.map((i) => i.id), ['status']);
          expect(s.item('send')!.why, 'Not now');
          final rows = CardMenu.build(record: s);
          final send = rows.firstWhere((r) => r.recordActionId == 'send');
          expect(send.isEnabled, isFalse);
          expect(send.why, 'Not now');
        },
      );
      test('empty and missing items list: nothing', () {
        expect(offered(_reply([])), isEmpty);
        expect(offered(<String, dynamic>{}), isEmpty);
        expect(offered({'items': 'garbage'}), isEmpty);
        expect(offered({'items': null}), isEmpty);
      });
      test('unknown ids and malformed entries are ignored', () {
        expect(
          offered(
            _reply([
              _item('approve'),
              {'label': 'No id'},
              7,
              null,
              _item('status'),
            ]),
          ),
          ['status'],
        );
      });
    },
  );

  group('the queue', () {
    late FakeSocket socket;
    late TicketRepository repo;
    final times = <int, List<DateTime>>{};
    var order = <int>[];

    setUp(() {
      _clock = DateTime(2026, 1, 1);
      times.clear();
      order = [];
      socket = FakeSocket()..goOnline();
      repo = TicketRepository(
        socket,
        FakeStore(user: 'ana'),
        FakeConversations(),
        now: () => _clock,
      )..onInit();
      socket.answers[RecordCmd.actions] = (Map<String, dynamic> a) {
        final id = a['id'] as int;
        order.add(id);
        (times[id] ??= []).add(_clock);
        return _reply([_item('send'), _item('status')]);
      };
    });

    tearDown(() => repo.onClose());

    void queueTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (t) async {
        await body(t);
        repo.releaseActions(List.generate(120, (i) => i + 1));
        await run(t, const Duration(seconds: 5));
      });
    }

    queueTest('newest first, one at a time, 300 ms apart', (t) async {
      repo.loadActions([5, 9, 7]);
      await t.pump();
      expect(order, [9]);
      await run(t, const Duration(milliseconds: 250));
      expect(order, [9]);
      await run(t, const Duration(milliseconds: 100));
      expect(order, [9, 7]);
      await run(t, const Duration(milliseconds: 300));
      expect(order, [9, 7, 5]);
    });

    queueTest('one in flight at a time', (t) async {
      final gate = Future<void>.delayed(const Duration(seconds: 2));
      socket.held[RecordCmd.actions] = gate;
      repo.loadActions([1, 2]);
      await t.pump();
      await run(t, const Duration(seconds: 1));
      expect(socket.count(RecordCmd.actions), 1);
      await run(t, const Duration(seconds: 2));
      await run(t, const Duration(milliseconds: 400));
      expect(socket.count(RecordCmd.actions), 2);
    });

    queueTest('de-dup, cache 60 s, then read again', (t) async {
      repo.loadActions([3, 3, 3]);
      await run(t, const Duration(seconds: 1));
      repo.loadActions([3]);
      await run(t, const Duration(seconds: 1));
      expect(socket.count(RecordCmd.actions), 1);
      repo.releaseActions([3, 3, 3, 3]);
      await run(t, const Duration(seconds: 61));
      repo.loadActions([3]);
      await run(t, const Duration(seconds: 1));
      expect(socket.count(RecordCmd.actions), 2);
    });

    queueTest('a card that scrolled away before its turn is not read', (
      t,
    ) async {
      repo.loadActions([1, 2, 3]);
      await t.pump();
      repo.releaseActions([1, 2]);
      await run(t, const Duration(seconds: 2));
      expect(order, [3]);
    });

    queueTest('paused in the background, resumes in front', (t) async {
      repo.didChangeAppLifecycleState(AppLifecycleState.paused);
      repo.loadActions([4]);
      await run(t, const Duration(seconds: 2));
      expect(socket.calls, isEmpty);
      repo.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await run(t, const Duration(seconds: 2));
      expect(socket.count(RecordCmd.actions), greaterThanOrEqualTo(1));
    });

    for (final code in ['rate_limited', 'busy', 'timeout']) {
      queueTest('backs off on $code and then succeeds', (t) async {
        var n = 0;
        socket.answers[RecordCmd.actions] = (Map<String, dynamic> a) {
          n++;
          times.putIfAbsent(1, () => []).add(_clock);
          if (n == 1) throw SocketCallError(code);
          return _reply([_item('send')]);
        };
        repo.loadActions([1]);
        await run(t, const Duration(milliseconds: 900));
        expect(n, 1);
        await run(t, const Duration(seconds: 2));
        expect(n, 2);
        expect(repo.itemsOf(1).map((i) => i.id), ['send']);
        final gap = times[1]![1].difference(times[1]![0]);
        expect(gap, greaterThanOrEqualTo(const Duration(seconds: 1)));
      });
    }

    queueTest('not_found: no actions, no error, not repeated', (t) async {
      socket.answers[RecordCmd.actions] = const SocketCallError('not_found');
      repo.loadActions([6]);
      await run(t, const Duration(seconds: 3));
      expect(repo.itemsOf(6), isEmpty);
      expect(socket.count(RecordCmd.actions), 1);
    });

    queueTest('100 cards scrolled past and 20 events stay in the budget', (
      t,
    ) async {
      final all = <DateTime>[];
      socket.answers[RecordCmd.actions] = (Map<String, dynamic> a) {
        all.add(_clock);
        return _reply([_item('send')]);
      };
      for (var id = 1; id <= 100; id++) {
        repo.loadActions([id]);
        await run(t, const Duration(milliseconds: 30));
        if (id % 5 == 0) repo.releaseActions([id - 4, id - 3, id - 2]);
      }
      for (var i = 0; i < 20; i++) {
        repo.onEvent({
          'type': 'sd_event',
          'event': RecordEvents.changed,
          'data': {'id': 96 + i % 5},
        });
        await run(t, const Duration(milliseconds: 100));
      }
      await run(t, const Duration(seconds: 40));
      expect(all, isNotEmpty);
      for (var i = 0; i < all.length; i++) {
        final inWindow = all
            .where(
              (x) =>
                  !x.isBefore(all[i]) && x.difference(all[i]) < ReadGate.window,
            )
            .length;
        expect(inWindow, lessThanOrEqualTo(ReadGate.budget));
      }
      for (var i = 1; i < all.length; i++) {
        expect(
          all[i].difference(all[i - 1]),
          greaterThanOrEqualTo(RecordActionsQueue.spacing),
        );
      }
    });

    queueTest('a stale record is read again only while on screen', (t) async {
      repo.loadActions([1]);
      await run(t, const Duration(seconds: 1));
      repo.onEvent({
        'type': 'sd_event',
        'event': RecordEvents.changed,
        'data': {'id': 1},
      });
      repo.onEvent({
        'type': 'sd_event',
        'event': RecordEvents.changed,
        'data': {'id': 2},
      });
      expect(repo.itemsOf(1), isEmpty, reason: 'hidden until refreshed');
      await run(t, const Duration(seconds: 2));
      expect(order, [1, 1]);
      expect(repo.itemsOf(1), isNotEmpty);
      repo.releaseActions([1]);
      repo.onEvent({
        'type': 'sd_event',
        'event': RecordEvents.changed,
        'data': {'id': 1},
      });
      await run(t, const Duration(seconds: 2));
      expect(order, [1, 1]);
    });
  });

  group('the card bar', () {
    late FakeSocket socket;
    late TicketRepository repo;

    setUp(() {
      socket = FakeSocket()..goOnline();
      repo = TicketRepository(
        socket,
        FakeStore(user: 'ana'),
        FakeConversations(),
        now: () => _clock,
      )..onInit();
    });

    tearDown(() => repo.onClose());

    Future<List<String>> pumpCard(WidgetTester t, List<Object?> items) async {
      final taps = <String>[];
      socket.answers[RecordCmd.actions] = _reply(items);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppFormCard(
                data: _card(24),
                isSent: false,
                onTap: () {},
                actions: RecordCardActions(
                  recordId: 24,
                  tickets: repo,
                  onAction: (_, id) => taps.add(id),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      return taps;
    }

    testWidgets('shows both buttons with no tap on the card, tap reports id', (
      t,
    ) async {
      final taps = await pumpCard(t, [_item('send'), _item('status')]);
      expect(socket.count(RecordCmd.actions), 1);
      expect(find.text('Send'), findsOneWidget);
      expect(find.text('Update status'), findsOneWidget);
      await t.tap(find.text('Update status'));
      await t.tap(find.text('Send'));
      expect(taps, ['status', 'send']);
    });

    testWidgets('no Send when the server sent none', (t) async {
      await pumpCard(t, [_item('status')]);
      expect(find.text('Send'), findsNothing);
      expect(find.text('Update status'), findsOneWidget);
    });

    testWidgets('no bar when nothing is enabled', (t) async {
      await pumpCard(t, [
        _item('send', enabled: false, why: 'x'),
        _item('status', enabled: false),
      ]);
      expect(find.text('Send'), findsNothing);
      expect(find.text('Update status'), findsNothing);
    });

    testWidgets('not_found and unreadable replies show no bar and no error', (
      t,
    ) async {
      socket.answers[RecordCmd.actions] = const SocketCallError('not_found');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFormCard(
              data: _card(24),
              isSent: false,
              onTap: () {},
              actions: RecordCardActions(
                recordId: 24,
                tickets: repo,
                onAction: (_, _) {},
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Send'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('the card drawn off screen (covered) reads nothing', (t) async {
      socket.answers[RecordCmd.actions] = _reply([_item('send')]);
      await t.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: false,
            child: Scaffold(
              body: RecordCardActions(
                recordId: 24,
                tickets: repo,
                onAction: (_, _) {},
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(socket.calls, isEmpty);
    });

    testWidgets('the scroll position stays when the bar appears', (t) async {
      socket.answers[RecordCmd.actions] = _reply([_item('send')]);
      final controller = ScrollController();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              reverse: true,
              controller: controller,
              children: [
                for (var i = 0; i < 30; i++)
                  if (i == 3)
                    AppFormCard(
                      data: _card(24),
                      isSent: false,
                      onTap: () {},
                      actions: RecordCardActions(
                        recordId: 24,
                        tickets: repo,
                        onAction: (_, _) {},
                      ),
                    )
                  else
                    SizedBox(height: 80, child: Text('row $i')),
              ],
            ),
          ),
        ),
      );
      controller.jumpTo(100);
      await t.pump();
      final before = controller.offset;
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Send'), findsOneWidget);
      expect(controller.offset, before);
    });
  });

  group('scans', () {
    test(
      'no view or widget reads record.actions; the queue is the only way',
      () {
        final files = [
          for (final dir in ['lib/features', 'lib/core/widgets'])
            ...Directory(dir)
                .listSync(recursive: true)
                .whereType<File>()
                .where(
                  (f) =>
                      f.path.endsWith('_view.dart') ||
                      f.path.contains('/widgets/'),
                ),
        ];
        for (final f in files) {
          final text = f.readAsStringSync();
          expect(text, isNot(contains('RecordCmd.actions')), reason: f.path);
          expect(text, isNot(contains('ensureMenu')), reason: f.path);
          expect(text, isNot(contains('tickets.actions(')), reason: f.path);
        }
      },
    );

    test(
      'chat and Work Space both build RecordCardActions for record cards',
      () {
        for (final p in const [
          'lib/features/conversation/conversation_view.dart',
          'lib/features/workspace/workspace_view.dart',
        ]) {
          expect(File(p).readAsStringSync(), contains('RecordCardActions('));
        }
      },
    );
  });
}
