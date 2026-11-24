import 'dart:async';

import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/socket/read_gate.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sv_support.dart';

const _rows = 'submissions.list';
const _mine = 'records.mine';
const _one = 'submission.get';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SvRig rig;
  late SvTable table;
  final times = <DateTime>[];

  /// Answers `submissions.list` from [rows] and records when each call came.
  void serve(
    List<Map<String, dynamic>> rows, {
    int pageSize = 500,
    Map<String, List<Map<String, dynamic>>> mine = const {},
    int minePageSize = 2,
  }) {
    final pager = listPager(rows, pageSize: pageSize);
    final mp = minePager(mine, pageSize: minePageSize);
    rig.socket.answers[_rows] = (args) {
      times.add(rig.clock.now);
      return pager(args);
    };
    rig.socket.answers[_mine] = (args) {
      times.add(rig.clock.now);
      return mp(args);
    };
  }

  Future<SvTable> openTickets() async {
    rig.socket.answers[SvCmd.sources] = captured('004');
    final all = await rig.repo.sources();
    return table = rig.repo.open(all.firstWhere((s) => s.name == 'tickets'));
  }

  setUp(() {
    rig = SvRig();
    times.clear();
  });

  group('paging', () {
    test(
      'submissions.list: 500 a page, offset += 500 while hasMore, 300 ms apart',
      () async {
        await openTickets();
        serve([for (var i = 1100; i > 0; i--) ownRow(i)]);
        await rig.repo.load(table);
        final calls = rig.socket.calls.where((c) => c.action == _rows).toList();
        expect(calls.map((c) => c.args['offset']), [0, 500, 1000]);
        expect(calls.every((c) => c.args['limit'] == 500), isTrue);
        expect(calls.every((c) => c.args['tstruct'] == 'tickets'), isTrue);
        expect(calls.every((c) => c.args['withDetails'] == true), isTrue);
        expect(table.rows.length, 1100);
        expect(table.phase.value, SvPhase.ready);
        expect(table.isPaging.value, isFalse);
        for (var i = 1; i < times.length; i++) {
          expect(
            times[i].difference(times[i - 1]).inMilliseconds,
            greaterThanOrEqualTo(300),
          );
        }
      },
    );

    test('at most 20 pages, then it says so', () async {
      await openTickets();
      serve([for (var i = 0; i < 12000; i++) ownRow(i + 1)]);
      await rig.repo.load(table);
      expect(rig.count(_rows), 20);
      expect(table.rows.length, 10000);
      expect(table.isCapped.value, isTrue);
      expect(table.total.value, 12000);
    });

    test('an empty page stops the read even when hasMore says more', () async {
      await openTickets();
      var n = 0;
      rig.socket.answers[_rows] = (args) {
        n++;
        return n == 1
            ? {
                'submissions': [ownRow(1)],
                'hasMore': true,
                'total': 5,
              }
            : {'submissions': <Object>[], 'hasMore': true, 'total': 5};
      };
      rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
      await rig.repo.load(table);
      expect(rig.count(_rows), 2);
      expect(table.rows.length, 1);
    });

    test('records.mine with/involved: offset += rows received, next is null, '
        '200 asked, short pages, 3 pages each', () async {
      await openTickets();
      serve(
        const [],
        mine: {
          'with': [for (var i = 100; i > 90; i--) mineRow(i)],
          'involved': [mineRow(200), mineRow(201)],
        },
      );
      await rig.repo.load(table);
      final with_ = rig.socket.calls.where(
        (c) => c.action == _mine && c.args['as'] == 'with',
      );
      expect(with_.map((c) => c.args['offset']), [null, 2, 4]);
      expect(with_.every((c) => c.args['limit'] == 200), isTrue);
      final inv = rig.socket.calls.where(
        (c) => c.action == _mine && c.args['as'] == 'involved',
      );
      expect(inv.length, 1);
      expect(table.rows.map((r) => r.id).toSet(), {
        100, 99, 98, 97, 96, 95, // 3 pages of 2
        200, 201,
      });
    });

    test('raised is never read by a structure table', () async {
      await openTickets();
      serve([ownRow(1)]);
      await rig.repo.load(table);
      expect(rig.socket.calls.where((c) => c.args['as'] == 'raised'), isEmpty);
    });
  });

  group('merge', () {
    test(
      'one row per id, the submissions.list copy wins, only this structure',
      () async {
        await openTickets();
        serve(
          [ownRow(39), ownRow(37)],
          mine: {
            'with': [
              mineRow(39),
              mineRow(47),
              mineRow(48, tstruct: 'requests'),
            ],
          },
          minePageSize: 10,
        );
        await rig.repo.load(table);
        expect(table.rows.map((r) => r.id).toList()..sort(), [37, 39, 47]);
        final kept = table.rowOf(39)!;
        expect(kept.canEdit, isTrue);
        expect(kept.isReceived, isFalse);
        expect(kept.byName, 'Ann Rao');
        final got = table.rowOf(47)!;
        expect(got.canEdit, isFalse);
        expect(got.isReceived, isTrue);
      },
    );

    test('rows are sorted newest first', () async {
      await openTickets();
      serve(
        [ownRow(1, ts: 100), ownRow(2, ts: 300)],
        mine: {
          'with': [mineRow(3, ts: 200)],
        },
        minePageSize: 10,
      );
      await rig.repo.load(table);
      expect(table.rows.map((r) => r.id), [2, 3, 1]);
    });

    test('a failing records.mine leaves the table as it was', () async {
      await openTickets();
      rig.socket.answers[_rows] = listPager([ownRow(1)]);
      rig.socket.answers[_mine] = const SocketCallError('error', 'boom');
      await rig.repo.load(table);
      expect(table.rows.map((r) => r.id), [1]);
      expect(table.phase.value, SvPhase.ready);
    });
  });

  group('hidden fields', () {
    test('a hidden value is never held, drawn or logged', () async {
      final lines = <String>[];
      final old = debugPrint;
      debugPrint = (msg, {wrapWidth}) => lines.add(msg ?? '');
      addTearDown(() => debugPrint = old);
      await openTickets();
      rig.socket.answers[_rows] = (args) =>
          args['offset'] == 0 ? captured('007') : captured('008');
      rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
      await rig.repo.load(table);
      expect(table.rows.length, 6);
      for (final r in table.rows) {
        expect(r.values.containsKey('secret'), isFalse);
        expect(r.values.toString().contains('HIDDEN'), isFalse);
      }
      expect(lines.join('\n').contains('HIDDEN'), isFalse);
      expect(lines.join('\n').contains('Printer'), isFalse);
      expect(lines.any((l) => l.contains('[records] smartview')), isTrue);
    });
  });

  group('states', () {
    test('not_found is a calm no-access state', () async {
      await openTickets();
      rig.socket.answers[_rows] = const SocketCallError(
        'not_found',
        'No such.',
      );
      await rig.repo.load(table);
      expect(table.phase.value, SvPhase.noAccess);
      expect(rig.count(_mine), 0);
    });

    test('an empty structure is empty after every list was read', () async {
      await openTickets();
      serve(const []);
      await rig.repo.load(table);
      expect(table.phase.value, SvPhase.empty);
      expect(rig.count(_mine), 2);
    });

    test('a structure with only received records is not empty', () async {
      await openTickets();
      serve(
        const [],
        mine: {
          'with': [mineRow(5)],
        },
      );
      await rig.repo.load(table);
      expect(table.phase.value, SvPhase.ready);
    });

    test('an error keeps its message and Retry reads again', () async {
      await openTickets();
      rig.socket.answers[_rows] = const SocketCallError('error', 'Down.');
      await rig.repo.load(table);
      expect(table.phase.value, SvPhase.error);
      expect(table.errorMessage.value, 'Down.');
      serve([ownRow(1)]);
      await rig.repo.refresh(table);
      expect(table.phase.value, SvPhase.ready);
    });

    test(
      'offline before any row: offline state; the socket is not used',
      () async {
        await openTickets();
        rig.socket.goOffline();
        await rig.repo.load(table);
        expect(table.phase.value, SvPhase.offline);
      },
    );

    test('a page that fails later keeps the rows and offers Retry', () async {
      await openTickets();
      final pager = listPager([for (var i = 0; i < 700; i++) ownRow(i + 1)]);
      rig.socket.answers[_rows] = (args) {
        if (args['offset'] == 500) {
          throw const SocketCallError('error', 'boom');
        }
        return pager(args);
      };
      rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
      await rig.repo.load(table);
      expect(table.rows.length, 500);
      expect(table.hasPartialError.value, isTrue);
      expect(table.phase.value, SvPhase.ready);
      expect(table.isPaging.value, isFalse);
    });

    test(
      'rows show page by page while the next page is still coming',
      () async {
        await openTickets();
        final gate = Completer<void>();
        final pager = listPager([for (var i = 0; i < 700; i++) ownRow(i + 1)]);
        rig.socket.answers[_mine] = {
          'submissions': <Object>[],
          'hasMore': false,
        };
        rig.socket.answers[_rows] = (args) {
          // The next call waits for the gate.
          rig.socket.held[_rows] = gate.future;
          return pager(args);
        };
        final run = rig.repo.load(table);
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(table.rows.length, 500);
        expect(table.phase.value, SvPhase.ready);
        expect(table.isPaging.value, isTrue);
        gate.complete();
        await run;
        expect(table.rows.length, 700);
        expect(table.isPaging.value, isFalse);
      },
    );
  });

  group('rate limit', () {
    test('rate_limited waits 1, 2, 3 s and then answers', () async {
      await openTickets();
      var n = 0;
      final pager = listPager([ownRow(1)]);
      rig.socket.answers[_rows] = (args) {
        if (++n <= 3) throw const SocketCallError('rate_limited', 'slow');
        return pager(args);
      };
      rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
      await rig.repo.load(table);
      expect(
        rig.clock.waits
            .where((d) => d >= const Duration(seconds: 1))
            .take(3)
            .toList(),
        [
          const Duration(seconds: 1),
          const Duration(seconds: 2),
          const Duration(seconds: 3),
        ],
      );
      expect(table.rows.length, 1);
    });

    test('five refusals in a row end as an error', () async {
      await openTickets();
      rig.socket.answers[_rows] = const SocketCallError('busy', 'busy');
      await rig.repo.load(table);
      expect(rig.count(_rows), 5);
      expect(table.phase.value, SvPhase.error);
    });

    test('never more than the shared budget in any 10 seconds', () async {
      await openTickets();
      serve([for (var i = 0; i < 5000; i++) ownRow(i + 1)]);
      await rig.repo.load(table);
      expect(times.length, greaterThan(10));
      for (final t in times) {
        final inWindow = times.where(
          (x) =>
              !x.isBefore(t) && x.difference(t) < const Duration(seconds: 10),
        );
        expect(inWindow.length, lessThanOrEqualTo(ReadGate.budget));
      }
    });
  });

  group('organisation switch', () {
    test(
      'clears the source list and the rows, and drops a read in flight',
      () async {
        await openTickets();
        expect(rig.repo.sourceReads, 1);
        await rig.repo.sources();
        expect(rig.repo.sourceReads, 1);
        final release = Completer<void>();
        rig.socket.held[_rows] = release.future;
        serve([ownRow(1), ownRow(2)]);
        final run = rig.repo.load(table);
        await Future<void>.delayed(Duration.zero);
        rig.store.switchTo('other', org: 'org2');
        await Future<void>.delayed(Duration.zero);
        release.complete();
        await run;
        expect(table.rows, isEmpty);
        expect(table.phase.value, SvPhase.loading);
        expect(rig.repo.keptSources, isNull);
        expect(rig.repo.sourceReads, 0);
        await rig.repo.sources();
        expect(rig.repo.sourceReads, 1);
      },
    );
  });

  group('source list', () {
    test('read once however often it is asked, suggestions included', () async {
      rig.socket.answers[SvCmd.sources] = captured('004');
      await rig.repo.sources();
      await rig.repo.suggestions('t');
      await rig.repo.suggestions('ti');
      await rig.repo.suggestions('tic');
      expect(rig.count(SvCmd.sources), 1);
      final s = await rig.repo.suggestions('tic');
      expect(s.map((x) => x.value), ['tickets']);
      expect(s.first.label, 'Tickets');
      expect(s.first.hint, 'your structure · 5 fields');
    });
  });

  group('live', () {
    Future<void> opened() async {
      await openTickets();
      serve([ownRow(10), ownRow(11)]);
      await rig.repo.load(table);
      rig.socket.calls.clear();
    }

    Map<String, dynamic> event(
      int id, {
      Map<String, dynamic>? record,
      String action = 'Status update',
    }) => {
      'type': 'sd_event',
      'event': 'submissions_changed',
      'data': {
        'id': id,
        'tstruct': 'tickets',
        'action': action,
        'record': ?record,
      },
    };

    test('data.record: the row changes in place, no command at all', () async {
      await opened();
      rig.repo.onEvent(
        event(
          10,
          record: {
            'by': 'svcapcpw1ann',
            'claimants': <String>[],
            'completion': 40,
            'final': false,
            'holder': 'svcapcpw1bob',
            'status': 'In progress',
            'ts': 5,
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(rig.socket.calls, isEmpty);
      expect(rig.repo.liveMode, 'record');
      final row = table.rowOf(10)!;
      expect(row.values['stage'], 'In progress');
      expect(row.holder, 'svcapcpw1bob');
      expect(row.completion, 40);
      expect(table.versions[10], 1);
      final live = rig.tickets.liveOf(10).value;
      expect(live.status, 'In progress');
      expect(live.holder, 'svcapcpw1bob');
    });

    test('no data.record: one debounced read of that record only', () async {
      await opened();
      rig.socket.answers[_one] = {
        'submission': ownRow(
          10,
          values: {'title': 'Row 10', 'stage': 'Closed', 'secret': 'HIDDEN'},
        ),
      };
      for (var i = 0; i < 5; i++) {
        rig.repo.onEvent(event(10));
      }
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(rig.repo.liveMode, 'refetch');
      expect(rig.count(_one), 1);
      expect(rig.count(_rows), 0);
      expect(rig.count(_mine), 0);
      expect(rig.clock.waits.contains(SvLimits.eventDebounce), isTrue);
      expect(table.rowOf(10)!.values['stage'], 'Closed');
      expect(table.rowOf(10)!.values.containsKey('secret'), isFalse);
      expect(table.rowOf(10)!.canEdit, isTrue);
    });

    test(
      'a record we do not hold, even with data.record, is read once',
      () async {
        await opened();
        rig.socket.answers[_one] = {'submission': ownRow(12)};
        rig.repo.onEvent(
          event(
            12,
            action: 'created',
            record: {'status': 'Open', 'holder': 'svcapcpw1ann'},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(rig.count(_one), 1);
        expect(table.rows.map((r) => r.id).toSet(), {10, 11, 12});
        expect(table.versions[12], 1);
      },
    );

    test('deleted removes the row with no command', () async {
      await opened();
      rig.repo.onEvent(event(11, action: 'deleted'));
      expect(table.rows.map((r) => r.id), [10]);
      expect(rig.socket.calls, isEmpty);
    });

    test('an event of another structure is ignored', () async {
      await opened();
      rig.repo.onEvent({
        'type': 'sd_event',
        'event': 'submissions_changed',
        'data': {'id': 10, 'tstruct': 'requests'},
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(rig.socket.calls, isEmpty);
    });

    test('an event with no id reads page 1 only (50 rows)', () async {
      await opened();
      rig.socket.answers[_rows] = (args) => {
        'submissions': [ownRow(13, ts: 9999999)],
        'hasMore': true,
        'total': 3,
      };
      rig.repo.onEvent({'type': 'sd_event', 'event': 'submissions_changed'});
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(rig.count(_rows), 1);
      expect(rig.socket.calls.single.args['limit'], 50);
      expect(rig.socket.calls.single.args['offset'], 0);
      expect(table.rowOf(13), isNotNull);
    });

    test(
      'a burst of 20 events stays inside the shared read budget',
      () async {
        await opened();
        times.clear();
        rig.socket.answers[_one] = (args) {
          times.add(rig.clock.now);
          return {'submission': ownRow(args['id'] as int)};
        };
        for (var i = 0; i < 20; i++) {
          rig.repo.onEvent(event(100 + i));
        }
        for (var i = 0; i < 60; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(times.length, 20);
        for (final t in times) {
          final inWindow = times.where(
            (x) =>
                !x.isBefore(t) && x.difference(t) < const Duration(seconds: 10),
          );
          expect(inWindow.length, lessThanOrEqualTo(ReadGate.budget));
        }
        expect(rig.count(_rows), 0);
      },
    );

    test('a structure change reads this table again, once', () async {
      await opened();
      serve([ownRow(10)]);
      rig.repo.onEvent({
        'type': 'sd_event',
        'event': 'tstructs_changed',
        'data': {'name': 'tickets', 'action': 'saved'},
      });
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(rig.count(_rows), 1);
      expect(table.rows.map((r) => r.id), [10]);
    });

    test('a closed table gets nothing', () async {
      await opened();
      rig.repo.close(table);
      rig.repo.onEvent(event(10));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(rig.socket.calls, isEmpty);
    });
  });

  group('rows on screen', () {
    // ts of row i (server order) over 1100 rows = 3 pages of 500.
    final cases = <String, int Function(int)>{
      'newest first (append path)': (i) => 5000 - i,
      'oldest first (full sort)': (i) => 5000 + i,
      'mixed pages (full sort)': (i) => 5000 + (i * 7919) % 1000,
      'equal times': (i) => 5000 - i ~/ 100,
    };
    for (final c in cases.entries) {
      test('${c.key}: same order and count as a full sort', () async {
        await openTickets();
        final ts = [for (var i = 0; i < 1100; i++) c.value(i)];
        serve([for (var i = 0; i < ts.length; i++) ownRow(i + 1, ts: ts[i])]);
        await rig.repo.load(table);
        expect(table.rows.length, 1100);
        expect([
          for (final r in table.rows) r.ts,
        ], [...ts]..sort((a, b) => b.compareTo(a)));
        expect({for (final r in table.rows) r.id}.length, 1100);
      });
    }

    test(
      'a page that sorts after what is shown is appended, not re-sorted',
      () async {
        await openTickets();
        final pager = listPager([
          for (var i = 0; i < 1100; i++) ownRow(i + 1, ts: 5000 - i),
        ]);
        rig.socket.answers[_rows] = (args) {
          if (args['offset'] != 0) {
            table.rows[0] = table.rows[0].copyWith(holder: 'marker');
          }
          return pager(args);
        };
        await rig.repo.load(table);
        expect(table.rows.length, 1100);
        expect(table.rows.first.holder, 'marker');
      },
    );

    test(
      'a page that sorts before what is shown re-sorts everything',
      () async {
        await openTickets();
        final pager = listPager([
          for (var i = 0; i < 1100; i++) ownRow(i + 1, ts: 5000 + i),
        ]);
        rig.socket.answers[_rows] = (args) {
          if (args['offset'] != 0) {
            table.rows[0] = table.rows[0].copyWith(holder: 'marker');
          }
          return pager(args);
        };
        await rig.repo.load(table);
        expect(table.rows.length, 1100);
        expect(table.rows.first.ts, 6099);
        expect(table.rows.any((r) => r.holder == 'marker'), isFalse);
      },
    );

    test('visible maps are shared, hidden keys are cut', () async {
      await openTickets();
      serve([
        ownRow(1, values: {'title': 'a', 'stage': 'Open', 'zz_hidden': 'x'}),
        ownRow(2),
      ]);
      await rig.repo.load(table);
      final byId = {for (final r in table.rows) r.id: r};
      expect(byId[1]!.values.containsKey('zz_hidden'), isFalse);
      expect(byId[1]!.values['title'], 'a');
      expect(byId[2]!.values['title'], 'Row 2');
    });
  });
}
