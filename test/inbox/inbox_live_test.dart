import 'dart:async';

import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/home_shell/home_tab.dart';
import 'package:connectum/features/inbox/inbox_live.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

Future<void> wait(int ms) =>
    Future<void>.delayed(Duration(milliseconds: ms)).then((_) => settle());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  late int queries;
  late List<Map<String, dynamic>> rows;

  Future<InboxRig> start({int n = 3}) async {
    final r = InboxRig();
    rig = r;
    addTearDown(r.dispose);
    queries = 0;
    rows = [for (var i = n; i >= 1; i--) record(i)];
    r.routes['records.query'] = (_) {
      queries++;
      return queryReply(rows);
    };
    r.controller.onInit();
    await settle();
    expect(queries, 1);
    return r;
  }

  int reads(String a) => rig.asked.where((x) => x == a).length;

  group('what a live read asks', () {
    test('a burst of 20 events is one read after the quiet time', () async {
      final r = await start();
      for (var i = 0; i < 20; i++) {
        r.emit('submissions_changed');
      }
      await settle();
      expect(queries, 1);
      await wait(120);
      expect(queries, 2);
      expect(reads('records.counts'), 2);
      expect(reads('req.list'), 2);
      expect(reads('records.mine'), 0);
      expect(r.argsOf('records.query').last['limit'], 100);
      expect(r.controller.live.reads, 1);
    });

    test('every event of the rule triggers one, others none', () async {
      final r = await start();
      r.emit('typing');
      r.emit('message');
      r.emit('request_created');
      await wait(100);
      expect(queries, 1);
      var expected = 1;
      for (final e in [
        'submissions_changed',
        'submission_approved',
        'submission_rejected',
        'submission_notice',
        'ticket_assigned',
        'task_assigned',
        'task_updated',
        'resync',
      ]) {
        r.emit(e);
        await wait(240);
        expected++;
        expect(queries, expected, reason: e);
      }
    });

    test(
      'asks for as many rows as are shown, rounded up, at most 200',
      () async {
        final r = await start(n: 130);
        expect(r.controller.rows, hasLength(130));
        r.emit('resync');
        await wait(120);
        expect(r.argsOf('records.query').last['limit'], 200);
        expect(r.argsOf('records.query').last['offset'], 0);
      },
    );

    test('the facets are read only while the filter panel is open', () async {
      final r = await start();
      r.emit('resync');
      await wait(120);
      expect(
        r.argsOf('records.query').where((a) => a['facets'] == true),
        isEmpty,
      );
    });

    test('a failed read keeps the list and the state', () async {
      final r = await start();
      r.routes['records.query'] = (_) => throw const SocketCallError('server');
      r.emit('submissions_changed');
      await wait(120);
      expect(r.ids, [3, 2, 1]);
      expect(r.controller.hasError.value, isFalse);
      expect(r.controller.isRefreshing.value, isFalse);
    });

    test(
      'rows change by id and the list keeps its filter and scroll',
      () async {
        final r = await start();
        rows = [record(4), ...rows];
        r.emit('task_updated');
        await wait(120);
        expect(r.ids, [4, 3, 2, 1]);
        expect(r.controller.filter.value.filterCount(), 0);
      },
    );

    test('a quiet read never shows the refresh state', () async {
      final r = await start();
      final seen = <bool>[];
      final w = r.controller.isRefreshing.listen(seen.add);
      addTearDown(w.cancel);
      r.emit('resync');
      await wait(120);
      expect(seen, isEmpty);
    });
  });

  group('one at a time, with a gap', () {
    test('events during a read give exactly one follow-up', () async {
      final r = await start();
      final held = Completer<Map<String, dynamic>>();
      r.routes['records.query'] = (_) {
        queries++;
        return held.future;
      };
      r.emit('resync');
      await wait(80);
      expect(queries, 2);
      for (var i = 0; i < 5; i++) {
        r.emit('submissions_changed');
      }
      await wait(100);
      expect(queries, 2);
      r.routes['records.query'] = (_) {
        queries++;
        return queryReply(rows);
      };
      held.complete(queryReply(rows));
      await wait(400);
      expect(queries, 3);
      await wait(400);
      expect(queries, 3);
    });

    test('two reads are at least the gap apart', () async {
      final r = await start();
      final starts = <DateTime>[];
      r.routes['records.query'] = (_) {
        queries++;
        starts.add(DateTime.now());
        return queryReply(rows);
      };
      r.emit('resync');
      await wait(60);
      r.emit('resync');
      await wait(400);
      expect(starts, hasLength(2));
      // The test clock stands still, so the gap is the whole 150 ms.
      expect(
        starts[1].difference(starts[0]),
        greaterThanOrEqualTo(const Duration(milliseconds: 140)),
      );
    });
  });

  group('visibility', () {
    test('a hidden tab reads nothing; showing it reads once', () async {
      final r = await start();
      r.shell.tab.value = HomeTab.chats;
      await settle();
      for (var i = 0; i < 4; i++) {
        r.emit('submissions_changed');
      }
      await wait(120);
      expect(queries, 1);
      expect(r.controller.live.isStale, isTrue);
      r.shell.tab.value = HomeTab.inbox;
      await wait(150);
      expect(queries, 2);
      expect(r.controller.live.isStale, isFalse);
      await wait(300);
      expect(queries, 2);
    });

    test(
      'a hidden tab with nothing missed reads nothing when shown later',
      () async {
        final r = await start();
        r.controller.live.cancel();
        r.shell.tab.value = HomeTab.chats;
        await settle();
        r.shell.tab.value = HomeTab.inbox;
        await wait(120);
        // The tab's own 30 s rule does not fire either: the list is fresh.
        expect(queries, 1);
      },
    );

    test('in the background nothing is read; resume reads once', () async {
      final r = await start();
      final b = TestWidgetsFlutterBinding.instance;
      b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      r.emit('task_assigned');
      r.emit('task_assigned');
      await wait(120);
      expect(queries, 1);
      b.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await wait(150);
      expect(queries, 2);
      await wait(300);
      expect(queries, 2);
    });

    test('a connection that came back is one re-read', () async {
      final r = await start();
      r.liveOnline.add(null);
      r.liveOnline.add(null);
      await wait(120);
      expect(queries, 2);
    });

    test('a connection back while hidden waits for the tab', () async {
      final r = await start();
      r.shell.tab.value = HomeTab.chats;
      await settle();
      r.liveOnline.add(null);
      await wait(120);
      expect(queries, 1);
      r.shell.tab.value = HomeTab.inbox;
      await wait(150);
      expect(queries, 2);
    });

    test('an event before the Inbox was opened is dropped', () async {
      final r = InboxRig();
      rig = r;
      addTearDown(r.dispose);
      r.shell.tab.value = HomeTab.chats;
      r.routes['records.query'] = (_) => queryReply([record(1)]);
      r.controller.onInit();
      r.emit('resync');
      await wait(120);
      expect(r.asked, isEmpty);
      expect(r.controller.live.isStale, isFalse);
    });
  });

  group('stale answers', () {
    test('a live answer older than a read of the person is dropped', () async {
      final r = await start();
      final live = Completer<Map<String, dynamic>>();
      r.routes['records.query'] = (_) {
        queries++;
        return live.future;
      };
      r.emit('resync');
      await wait(80);
      expect(queries, 2);
      // The person pulls to refresh: a newer read with a new row.
      r.routes['records.query'] = (_) {
        queries++;
        return queryReply([record(9), ...rows]);
      };
      // The shared gate runs one read at a time: the person's read starts
      // when the live one has answered, and the live answer is then stale.
      final mine = r.controller.refreshList();
      await settle();
      live.complete(queryReply(rows));
      await mine;
      await wait(100);
      expect(r.ids.first, 9);
    });

    test('a read of the person waits for none: live waits for it', () async {
      final r = await start();
      final mine = Completer<Map<String, dynamic>>();
      r.routes['records.query'] = (_) {
        queries++;
        return mine.future;
      };
      final f = r.controller.refreshList();
      await settle();
      expect(queries, 2);
      r.emit('resync');
      await wait(120);
      expect(queries, 2);
      r.routes['records.query'] = (_) {
        queries++;
        return queryReply([record(7)]);
      };
      mine.complete(queryReply([record(8)]));
      await f;
      await wait(300);
      expect(queries, 3);
      expect(r.ids, [7]);
    });

    test('a filter chosen during a live read is not overwritten', () async {
      final r = await start();
      final live = Completer<Map<String, dynamic>>();
      r.routes['records.query'] = (_) {
        queries++;
        return live.future;
      };
      r.emit('resync');
      await wait(80);
      r.routes['records.query'] = (_) {
        queries++;
        return queryReply([record(5)]);
      };
      r.controller.clearFilter();
      await settle();
      expect(r.ids, isEmpty);
      live.complete(queryReply(rows));
      await wait(100);
      expect(r.ids, [5]);
    });
  });

  group('approvals', () {
    test('request events change the count and the open pane', () async {
      final r = await start();
      r.controller.openApprovals();
      expect(r.controller.approvals.rows, isEmpty);
      r.routes['req.list'] = (_) => {
        'requests': [
          {
            'id': 7,
            'type': 'submission',
            'status': 'pending',
            'from': 'rhea',
            'fromName': 'Rhea',
            'approvers': ['ana'],
            'direction': 'incoming',
            'canRespond': true,
            'createdTs': 1000,
            'data': {'caption': 'Expense 7'},
          },
        ],
        'total': 1,
        'hasMore': false,
      };
      r.approvalRepo.onEvent({
        'type': 'sd_event',
        'event': 'request_created',
        'data': {'request': (await r.routes['req.list']!({}))['requests'][0]},
      });
      await wait(400);
      expect(r.controller.approvals.count, 1);
      expect(r.controller.approvals.rows.map((a) => a.id), [7]);
      expect(queries, 1);
    });
  });

  group('session', () {
    test('a session change cancels pending work', () async {
      final r = await start();
      r.emit('resync');
      await settle();
      r.store.switchTo('bea');
      await wait(150);
      expect(r.argsOf('records.query').length, 2);
      // The only extra read is the new session's own first one.
      expect(r.controller.live.reads, 0);
    });

    test('signed out: events are dropped', () async {
      final r = await start();
      r.store.switchTo(null);
      await settle();
      r.emit('resync');
      await wait(120);
      expect(r.controller.live.reads, 0);
    });
  });

  group('InboxLive on its own', () {
    testWidgets('the gap holds against a clock', (tester) async {
      var now = DateTime(2026, 11, 24, 12);
      var runs = 0;
      final live = InboxLive(
        state: () => InboxLiveState.active,
        isBusy: () => false,
        read: () async => runs++,
        now: () => now,
      )..start();
      addTearDown(live.dispose);
      live.onEvent({'type': 'sd_event', 'event': 'resync'});
      await tester.pump(const Duration(milliseconds: 299));
      expect(runs, 0);
      await tester.pump(const Duration(milliseconds: 2));
      expect(runs, 1);
      // 500 ms later (clock) another event: it waits until 2 s after the end.
      now = now.add(const Duration(milliseconds: 500));
      live.onEvent({'type': 'sd_event', 'event': 'resync'});
      await tester.pump(const Duration(milliseconds: 1000));
      expect(runs, 1);
      await tester.pump(const Duration(milliseconds: 600));
      expect(runs, 2);
    });

    testWidgets('each event moves the quiet time', (tester) async {
      var runs = 0;
      final live = InboxLive(
        state: () => InboxLiveState.active,
        isBusy: () => false,
        read: () async => runs++,
      )..start();
      addTearDown(live.dispose);
      for (var i = 0; i < 5; i++) {
        live.onEvent({'type': 'ticket_assigned'});
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(runs, 0);
      await tester.pump(const Duration(milliseconds: 150));
      expect(runs, 1);
    });
  });
}
