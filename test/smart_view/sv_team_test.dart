import 'dart:async';

import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/data/repositories/smart_view_repository.dart';
import 'package:connectum/data/smart_view/engine/sv_engine.dart';
import 'package:connectum/data/smart_view/engine/sv_values.dart';
import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/smart_view_commands.dart';
import 'package:connectum/data/smart_view/sv_columns.dart';
import 'package:connectum/data/smart_view/sv_query.dart';
import 'package:connectum/data/smart_view/sv_saved_view.dart';
import 'package:connectum/data/smart_view/sv_team.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/smart_view/widgets/sv_filter_draft.dart';
import 'package:connectum/features/smart_view/widgets/sv_team_lines.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'sv_support.dart';

const _query = RecordCmd.query;
const _list = 'submissions.list';
const _mine = 'records.mine';

SvCondition _team(List<String> v) => SvCondition(SvTeamCols.team, 'in', v);
SvCondition _linked(List<String> v) => SvCondition(SvTeamCols.linked, 'in', v);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the reserved conditions are not columns', () {
    final table = EngineTable(
      const [EngineCol('title', 'Title', EngineType.text)],
      [
        {'title': 'a'},
        {'title': 'b'},
      ],
    );

    test('the engine skips them: no row is hidden', () {
      expect(
        SvEngine.filter(
          table,
          conditions: [
            _team(['ravi']),
            _linked(['tagged']),
          ],
        ),
        [0, 1],
      );
    });

    test('a column condition next to them still works', () {
      expect(
        SvEngine.filter(
          table,
          conditions: [
            _team(['ravi']),
            const SvCondition('title', 'equals', 'b'),
          ],
        ),
        [1],
      );
    });

    test('even a malformed one (wrong op or value) hides nothing', () {
      expect(
        SvEngine.filter(
          table,
          conditions: const [
            SvCondition('__team', 'eq', 'ravi'),
            SvCondition('__linked', 'in', 'x'),
          ],
        ),
        [0, 1],
      );
    });

    test('a query: team lines are not column filters, not a narrowing', () {
      final q = SmartViewQuery(
        conditions: [
          _team(['ravi']),
          _linked(['pending']),
        ],
      );
      expect(q.activeConditions.length, 2);
      expect(q.columnConditions, isEmpty);
      expect(q.isFiltering, isFalse);
      expect(q.team!.members, ['ravi']);
      expect(q.team!.linked, ['pending']);
    });

    test('SvEngineInput keeps every row under them', () {
      final input = SvEngineInput.of(
        SmartViewColumns.of(sourceNamed('tickets')),
        [
          for (var i = 1; i <= 3; i++)
            SvRow.tryParse(ownRow(i), isReceived: false)!,
        ],
      );
      final q = SmartViewQuery(
        conditions: [
          _team(['ravi']),
        ],
      );
      expect(input.apply(q).length, 3);
      expect(
        input.count(
          conditions: [
            _team(['ravi']),
            _linked(['tagged']),
          ],
        ),
        3,
      );
    });
  });

  group('SvTeam', () {
    test('of: none set is null; only known ways; members as chosen', () {
      expect(SvTeam.of(const []), isNull);
      expect(SvTeam.of([_team([])]), isNull);
      final f = SvTeam.of([
        _team(['ravi', 'sana', 'ravi']),
        _linked(['tagged', 'bogus', 'pending']),
      ])!;
      expect(f.members, ['ravi', 'sana']);
      expect(f.linked, ['tagged', 'pending']);
    });

    test('toArgs sends only what is set, never an empty team', () {
      expect(const SvTeamFilter(members: ['a']).toArgs(), {
        'members': ['a'],
      });
      expect(const SvTeamFilter(linked: ['sentTo']).toArgs(), {
        'linked': ['sentTo'],
      });
      expect(const SvTeamFilter().toArgs(), isEmpty);
    });

    test('at most 50 members are asked for', () {
      final f = SvTeam.of([
        _team([for (var i = 0; i < 60; i++) 'u$i']),
      ])!;
      expect(f.members.length, 50);
    });

    test('withLines replaces both lines and keeps column conditions', () {
      final kept = const SvCondition('title', 'contains', 'x');
      final out = SvTeam.withLines(
        [
          kept,
          _team(['old']),
        ],
        ['ravi'],
        const [],
      );
      expect(out, [
        kept,
        _team(['ravi']),
      ]);
      expect(SvTeam.withLines(out, const [], const []), [kept]);
    });

    test('chip text: names, ways and the +N tail', () {
      String name(String u) => u == 'ravi'
          ? 'Ravi'
          : u == 'sana'
          ? 'Sana'
          : u;
      expect(
        SvTeam.chipText(_team(['ravi', 'sana']), name),
        'My team: Ravi, Sana',
      );
      expect(
        SvTeam.chipText(_team(['ravi', 'sana', 'x', 'y']), name),
        'My team: Ravi, Sana +2',
      );
      expect(
        SvTeam.chipText(_linked(['tagged', 'pending']), name),
        'Linked as: Tagged to, Pending with team',
      );
    });

    test('every way has words and a meaning', () {
      expect(SvTeam.ways.map((w) => w.id), [
        'tagged',
        'assignedTo',
        'assignedBy',
        'sentTo',
        'sentBy',
        'raisedBy',
        'raisedTo',
        'pending',
        'requests',
      ]);
      expect(
        SvTeam.ways.every((w) => w.label.isNotEmpty && w.hint.isNotEmpty),
        isTrue,
      );
    });
  });

  group('saved views', () {
    final known = {'title', 'stage'};

    test('round trip: save with both lines, restore, same query', () {
      final state = SvViewState(
        query: SmartViewQuery(
          conditions: [
            const SvCondition('title', 'contains', 'x'),
            _team(['ravi', 'sana']),
            _linked(['tagged', 'pending']),
          ],
        ),
      );
      final saved = SvSavedView.fresh('1', 'Mine', state);
      expect(saved.filters, [
        {'col': 'title', 'op': 'contains', 'value': 'x'},
        {
          'col': '__team',
          'op': 'in',
          'value': ['ravi', 'sana'],
        },
        {
          'col': '__linked',
          'op': 'in',
          'value': ['tagged', 'pending'],
        },
      ]);
      final again = SvSavedView.tryParse(saved.toJson())!;
      expect(again.toState(known), state);
      expect(again.toState(known).query.team, state.query.team);
    });

    test(
      'a web view with the lines opens: they are not dropped as unknown columns',
      () {
        final v = SvSavedView.tryParse({
          'id': 'w',
          'name': 'Web',
          'filters': [
            {
              'col': '__team',
              'op': 'in',
              'value': ['ravi'],
            },
            {
              'col': '__linked',
              'op': 'in',
              'value': ['raisedBy'],
            },
            {'col': 'gone', 'op': 'equals', 'value': 'x'},
          ],
        })!;
        final q = v.toState(known).query;
        expect(q.conditions, [
          _team(['ravi']),
          _linked(['raisedBy']),
        ]);
      },
    );

    test('a malformed line is dropped, an older list works as before', () {
      final v = SvSavedView.tryParse({
        'id': 'w',
        'name': 'Odd',
        'filters': [
          {'col': '__team', 'op': 'eq', 'value': 'ravi'},
          {'col': '__linked', 'op': 'in', 'value': 'tagged'},
          {'col': 'title', 'op': 'equals', 'value': 'a'},
        ],
      })!;
      expect(v.toState(known).query.conditions, [
        const SvCondition('title', 'equals', 'a'),
      ]);
      final old = SvSavedView.tryParse({'id': 'o', 'name': 'Old'})!;
      expect(old.toState(known).query.team, isNull);
    });

    test(
      'a view with the lines differs from one without (it is "changed")',
      () {
        const plain = SvViewState();
        final withLines = SvViewState(
          query: SmartViewQuery(
            conditions: [
              _team(['a']),
            ],
          ),
        );
        expect(withLines == plain, isFalse);
        expect(withLines.filterCount, 1);
      },
    );
  });

  group('the read', () {
    late SvRig rig;
    late SvTable table;

    Future<void> open() async {
      rig.socket.answers[SvCmd.sources] = captured('004');
      final all = await rig.repo.sources();
      table = rig.repo.open(all.firstWhere((s) => s.name == 'tickets'));
    }

    List<({String action, Map<String, dynamic> args})> calls(String a) =>
        rig.socket.calls.where((c) => c.action == a).toList();

    void serveQuery(List<Map<String, dynamic>> rows, {int page = 200}) {
      final pager = listPager(rows, pageSize: page);
      rig.socket.answers[_query] = pager;
    }

    setUp(() => rig = SvRig());

    test('no team: submissions.list as before, never records.query', () async {
      await open();
      rig.socket.answers[_list] = listPager([ownRow(1)]);
      rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
      await rig.repo.load(table);
      expect(calls(_list), isNotEmpty);
      expect(calls(_query), isEmpty);
    });

    test(
      'team set: records.query with exactly forms, team, limit, offset, withDetails',
      () async {
        await open();
        serveQuery([ownRow(1)]);
        await rig.repo.applyTeam(
          table,
          const SvTeamFilter(members: ['ravi'], linked: ['tagged']),
        );
        expect(calls(_query).single.args, {
          'forms': ['tickets'],
          'team': {
            'members': ['ravi'],
            'linked': ['tagged'],
          },
          'limit': 200,
          'offset': 0,
          'withDetails': true,
        });
        expect(calls(_list), isEmpty);
        expect(calls(_mine), isEmpty);
        expect(table.rows.length, 1);
        expect(table.phase.value, SvPhase.ready);
      },
    );

    test('only the set half is sent', () async {
      await open();
      serveQuery([ownRow(1)]);
      await rig.repo.applyTeam(table, const SvTeamFilter(linked: ['pending']));
      expect(calls(_query).single.args['team'], {
        'linked': ['pending'],
      });
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
      expect(calls(_query).last.args['team'], {
        'members': ['a'],
      });
    });

    test('pages by offset while hasMore, 200 a page', () async {
      await open();
      serveQuery([for (var i = 450; i > 0; i--) ownRow(i)]);
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
      expect(calls(_query).map((c) => c.args['offset']), [0, 200, 400]);
      expect(calls(_query).every((c) => c.args['limit'] == 200), isTrue);
      expect(table.rows.length, 450);
      expect(table.total.value, 450);
      expect(table.isPaging.value, isFalse);
    });

    test('removing both lines reads the plain list again', () async {
      await open();
      serveQuery([ownRow(1)]);
      rig.socket.answers[_list] = listPager([ownRow(1), ownRow(2)]);
      rig.socket.answers[_mine] = {'submissions': <Object>[], 'hasMore': false};
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
      expect(table.rows.length, 1);
      await rig.repo.applyTeam(table, null);
      expect(calls(_list), isNotEmpty);
      expect(table.rows.length, 2);
      expect(table.team, isNull);
    });

    test('the same lines read nothing again', () async {
      await open();
      serveQuery([ownRow(1)]);
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
      expect(calls(_query).length, 1);
    });

    test(
      'invalid keeps the previous rows and shows the server message',
      () async {
        await open();
        serveQuery([ownRow(1), ownRow(2)]);
        await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
        rig.socket.answers[_query] = const SocketCallError(
          'invalid',
          'Bad team list',
        );
        await rig.repo.applyTeam(
          table,
          const SvTeamFilter(linked: ['pending']),
        );
        expect(table.rows.length, 2);
        expect(table.phase.value, SvPhase.ready);
        expect(table.hasPartialError.value, isTrue);
        expect(table.errorMessage.value, 'Bad team list');
      },
    );

    test('a late answer of an older team is dropped', () async {
      await open();
      final gate = Completer<void>();
      rig.socket.held[_query] = gate.future;
      rig.socket.answers[_query] = (args) {
        final who = ((args['team'] as Map)['members'] as List).first;
        return {
          'submissions': [ownRow(who == 'a' ? 1 : 2)],
          'total': 1,
          'hasMore': false,
        };
      };
      final first = rig.repo.applyTeam(
        table,
        const SvTeamFilter(members: ['a']),
      );
      await Future<void>.delayed(Duration.zero);
      final second = rig.repo.applyTeam(
        table,
        const SvTeamFilter(members: ['b']),
      );
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([first, second]);
      expect(table.rows.map((r) => r.id), [2]);
    });

    test('rate_limited waits 1, 2, 3 s through the gate and answers', () async {
      await open();
      var n = 0;
      final pager = listPager([ownRow(1)]);
      rig.socket.answers[_query] = (args) {
        if (++n <= 3) throw const SocketCallError('rate_limited', 'slow');
        return pager(args);
      };
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
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

    test('files with only {id, name, mime, size} do not break a row', () async {
      await open();
      final row = ownRow(1);
      (row['files'] as Map?)?.clear();
      row['files'] = {
        'attach': [
          {'id': 'f1', 'name': 'a.pdf', 'mime': 'application/pdf', 'size': 12},
        ],
      };
      serveQuery([row]);
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
      expect(table.rows.length, 1);
    });

    test('a live event for a record not held re-reads by the lines', () async {
      await open();
      serveQuery([ownRow(1)]);
      await rig.repo.applyTeam(table, const SvTeamFilter(members: ['a']));
      rig.socket.calls.clear();
      rig.repo.onEvent({
        'type': 'submissions_changed',
        'data': {'tstruct': 'tickets', 'id': 99},
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await Future<void>.delayed(Duration.zero);
      expect(calls('submission.get'), isEmpty);
      expect(calls(_query).length, 1);
    });
  });

  group('the sheet lines', () {
    SvFilterDraft draftOf(List<SvCondition> start) => SvFilterDraft(
      SvEngineInput.of(SmartViewColumns.of(sourceNamed('tickets')), [
        SvRow.tryParse(ownRow(1), isReceived: false)!,
      ]),
      SmartViewQuery(conditions: start),
    );

    test('the draft holds the lines apart from the column rows', () {
      final d = draftOf([
        const SvCondition('title', 'contains', 'x'),
        _team(['ravi']),
        _linked(['tagged']),
      ]);
      expect(d.rows.length, 1);
      expect(d.members, ['ravi']);
      expect(d.linked, ['tagged']);
      expect(d.conditions.length, 3);
    });

    test('choosing and removing members and ways', () {
      final d = draftOf(const []);
      d.toggleMember('ravi');
      d.toggleMember('sana');
      d.toggleWay('pending');
      expect(d.conditions, [
        _team(['ravi', 'sana']),
        _linked(['pending']),
      ]);
      d.toggleMember('ravi');
      d.toggleWay('pending');
      expect(d.conditions, [
        _team(['sana']),
      ]);
      d.clear();
      expect(d.conditions, isEmpty);
      expect(d.hasAny, isFalse);
    });

    Widget host(SvFilterDraft d, SvTeamChoices c, {double w = 320}) =>
        MediaQuery(
          data: MediaQueryData(
            size: Size(w, 800),
            textScaler: const TextScaler.linear(1.5),
          ),
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: w,
                child: SingleChildScrollView(
                  child: SvTeamLines(draft: d, choices: c),
                ),
              ),
            ),
          ),
        );

    SvTeamChoices choices(List<String> users) => SvTeamChoices(
      users: users.obs,
      nameOf: (u) =>
          u == 'longname' ? 'Bartholomew Maximilian Featherstonehaugh' : u,
      pictureOf: (_) => null,
    );

    testWidgets('nobody reports to the person: no lines', (tester) async {
      await tester.pumpWidget(host(draftOf(const []), choices([])));
      expect(find.text('My team'), findsNothing);
      expect(find.text('Linked as'), findsNothing);
    });

    testWidgets('somebody does: both lines, tapping chooses', (tester) async {
      final d = draftOf(const []);
      await tester.pumpWidget(host(d, choices(['ravi', 'sana'])));
      expect(find.text('My team'), findsOneWidget);
      expect(find.text('Linked as'), findsOneWidget);
      expect(find.text('None chosen means any way.'), findsOneWidget);
      await tester.tap(find.text('ravi'));
      await tester.tap(find.text('Tagged to'));
      await tester.pump();
      expect(d.members, ['ravi']);
      expect(d.linked, ['tagged']);
      expect(find.textContaining('Tagged to: '), findsOneWidget);
      expect(find.text('None chosen means any way.'), findsNothing);
    });

    testWidgets('320 px wide at text scale 1.5: no overflow', (tester) async {
      final d = draftOf([
        _team(['longname']),
        _linked(['pending', 'assignedBy']),
      ]);
      await tester.pumpWidget(
        host(d, choices(['longname', 'ravi', 'sana', 'x1', 'x2'])),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  });
}
