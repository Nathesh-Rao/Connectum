import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_page.dart';
import 'package:connectum/features/inbox/models/inbox_query.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:connectum/features/inbox/models/inbox_sort.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ports of `tests/frontend/inboxQuery.test.mjs` and the sort cases of
/// `inboxFilters.test.mjs` (the web repo).
InboxCondition cond(
  String field, {
  String op = 'contains',
  String value = '',
  String value2 = '',
  String join = 'and',
}) => InboxCondition(
  field: field,
  op: op,
  value: value,
  value2: value2,
  join: join,
);

InboxRow row(String id, String subject, int ts) => InboxRow(
  id: id.codeUnitAt(0),
  formId: 't',
  form: 'T',
  subject: subject,
  holder: '',
  raiser: '',
  ts: ts,
);

List<String> subjects(List<InboxRow> r) => [for (final x in r) x.subject];

void main() {
  group('operators', () {
    test(
      'follow the kind of field, and every one is a word the server knows',
      () {
        const server = [
          'eq',
          'ne',
          'in',
          'nin',
          'contains',
          'starts',
          'ends',
          'gt',
          'gte',
          'lt',
          'lte',
          'between',
          'empty',
          'notempty',
        ];
        for (final k in const ['text', 'number', 'date', 'bool']) {
          for (final (id, _) in InboxOps.of(k)) {
            expect(server, contains(id), reason: '$k: $id');
          }
        }
        expect(InboxOps.kindOfType('number'), 'number');
        expect(InboxOps.kindOfType('date'), 'date');
        expect(InboxOps.kindOfType('bool'), 'bool');
        expect(InboxOps.kindOfType('list'), 'text');
        expect(InboxOps.kindOfType(null), 'text');
        expect(InboxOps.of('nothing'), InboxOps.text);
        expect(InboxOps.needsValue('empty'), isFalse);
        expect(InboxOps.needsValue('notempty'), isFalse);
        expect(InboxOps.needsValue('eq'), isTrue);
      },
    );
  });

  group('condition', () {
    test('is ready with a field, an operator and what the operator needs', () {
      InboxCondition c(
        String op, {
        String v = '',
        String v2 = '',
        String f = 'title',
      }) => cond(f, op: op, value: v, value2: v2);
      expect(c('contains', v: 'x').isReady, isTrue);
      expect(
        c('contains', v: '  ').isReady,
        isFalse,
        reason: 'blank is no value',
      );
      expect(c('empty').isReady, isTrue, reason: 'empty needs no value');
      expect(
        c('between', v: '1').isReady,
        isFalse,
        reason: 'between needs two',
      );
      expect(c('between', v: '1', v2: '5').isReady, isTrue);
      expect(c('contains', v: 'x', f: '').isReady, isFalse);
      expect(c('', v: 'x').isReady, isFalse);
      expect(InboxCondition.forField('n', 'number').op, 'eq');
      expect(InboxCondition.forField('n', 'date').join, 'and');
    });
  });

  group('blocks', () {
    test(
      'a block that says nothing is dropped; a form, a person or a ready condition says something',
      () {
        expect(InboxBlock().isActive, isFalse);
        expect(InboxBlock(forms: ['Tickets']).isActive, isTrue);
        expect(InboxBlock(createdBy: ['me']).isActive, isTrue);
        expect(InboxBlock(sentBy: ['ravi']).isActive, isTrue);
        expect(InboxBlock(sentTo: ['sana']).isActive, isTrue);
        expect(
          InboxBlock(conditions: [cond('title')]).isActive,
          isFalse,
          reason: 'a condition with no value does not count',
        );
        expect(
          InboxBlock(conditions: [cond('title', op: 'empty')]).isActive,
          isTrue,
        );
        expect(const InboxFilter().filterCount(), 0);
        expect(
          InboxFilter(
            blocks: [
              InboxBlock(),
              InboxBlock(forms: ['A']),
            ],
          ).filterCount(),
          1,
        );
      },
    );

    test(
      'the groups sent are the blocks that say something, with only their ready conditions',
      () {
        final f = InboxFilter(
          blocks: [
            InboxBlock(),
            InboxBlock(
              forms: ['Tickets'],
              createdBy: ['me', 'ravi'],
              sentTo: ['sana'],
              conditions: [
                cond('title', value: ' lap '),
                cond('stage', op: 'eq', join: 'or'),
                cond(
                  'hours',
                  op: 'between',
                  value: '1',
                  value2: '5',
                  join: 'or',
                ),
                cond('due', op: 'empty', value: 'ignored'),
              ],
            ),
          ],
        );
        expect(f.groups, [
          {
            'form': 'Tickets',
            'createdBy': ['me', 'ravi'],
            'sentTo': ['sana'],
            'conditions': [
              {
                'field': 'title',
                'op': 'contains',
                'join': 'and',
                'value': 'lap',
              },
              {
                'field': 'hours',
                'op': 'between',
                'join': 'or',
                'value': '1',
                'value2': '5',
              },
              {'field': 'due', 'op': 'empty', 'join': 'and'},
            ],
          },
        ]);
        expect(const InboxFilter().groups, isEmpty);
      },
    );

    test('are limited as the server limits them', () {
      final many = InboxFilter(
        blocks: [
          for (var i = 0; i < 15; i++) InboxBlock(forms: ['A']),
        ],
      );
      expect(many.groups.length, InboxFilterLimits.maxBlocks);
      final conds = [for (var i = 0; i < 25; i++) cond('t', op: 'empty')];
      final f = InboxFilter(
        blocks: [
          InboxBlock(forms: ['A'], conditions: conds),
        ],
      );
      expect(
        (f.groups.single['conditions'] as List).length,
        InboxFilterLimits.maxConditions,
      );
    });

    test(
      'a block of several forms is one group for each, with the same people; conditions are for ONE form',
      () {
        final c = cond('title', value: 'x');
        final many = InboxBlock(
          forms: ['A', 'B', 'C'],
          createdBy: ['me'],
          sentTo: ['ravi'],
          conditions: [c],
        );
        expect(InboxFilter(blocks: [many]).groups, [
          for (final f in ['A', 'B', 'C'])
            {
              'form': f,
              'createdBy': ['me'],
              'sentTo': ['ravi'],
              'conditions': <Object>[],
            },
        ]);
        expect(
          (many.copyWith(forms: ['A']).groups.single['conditions'] as List)
              .length,
          1,
        );
        expect(InboxBlock(createdBy: ['me']).groups, [
          {
            'createdBy': ['me'],
            'conditions': <Object>[],
          },
        ]);
        final twelve = InboxBlock(forms: [for (var i = 0; i < 12; i++) 'F$i']);
        expect(
          InboxFilter(blocks: [twelve]).groups.length,
          InboxFilterLimits.maxBlocks,
        );
      },
    );

    test('every block and condition has its own id', () {
      final ids = [
        InboxBlock().id,
        InboxBlock().id,
        InboxCondition.forField('a').id,
        InboxCondition.forField('b').id,
      ];
      expect(ids.toSet().length, 4);
    });

    test('a block read back from a saved view is checked', () {
      final b = InboxBlock.revive([
        {
          'id': 'q1',
          'form': 'Tickets',
          'createdBy': ['me', 5, '', 'x' * 300],
          'sentBy': 'no',
          'sentTo': ['ravi'],
          'extra': 1,
          'conditions': [
            {
              'id': 'c1',
              'field': 'title',
              'op': 'eq',
              'value': 'x',
              'value2': 3,
              'join': 'or',
            },
            null,
            'x',
            {'field': 'a', 'op': 'empty', 'join': 'weird'},
          ],
        },
      ]).single;
      expect(b.createdBy, ['me']);
      expect(b.sentBy, isEmpty);
      expect(b.sentTo, ['ravi']);
      expect(b.id, 'q1');
      expect(b.forms, ['Tickets'], reason: 'an older screen named ONE form');
      expect(b.conditions.length, 2);
      expect(b.conditions[0].toJson(), {
        'id': 'c1',
        'field': 'title',
        'op': 'eq',
        'value': 'x',
        'value2': '',
        'join': 'or',
      });
      expect(b.conditions[1].join, 'and');
      expect(b.conditions[1].id, isNot('c1'));
      expect(InboxBlock.revive('x'), isEmpty);
      expect(InboxBlock.revive(null), isEmpty);
      expect(InboxBlock.revive([1, null, <Object>[], 'x']), isEmpty);
      expect(
        InboxBlock.revive([
          for (var i = 0; i < 30; i++) <String, Object>{},
        ]).length,
        10,
      );
      expect(
        InboxBlock.revive([
          {'id': 'bad id!'},
        ]).single.id.startsWith('q'),
        isTrue,
      );
      expect(
        InboxBlock.revive([
          {
            'id': 'q1',
            'forms': ['A', 5, 'B'],
          },
        ]).single.forms,
        ['A', 'B'],
      );
      expect(
        InboxBlock.revive([
          {'id': 'q1', 'form': 'x' * 500},
        ]).single.forms,
        isEmpty,
      );
    });
  });

  group('request arguments', () {
    test('nothing chosen sends nothing; forms and blocks are sent', () {
      expect(const InboxFilter().toQuery().toArgs(limit: 50), {
        'limit': 50,
        'offset': 0,
      });
      expect(const InboxFilter(forms: ['A', 'B']).toQuery().toArgs()['forms'], [
        'A',
        'B',
      ]);
      final f = InboxFilter(
        forms: ['A'],
        blocks: [
          InboxBlock(forms: ['A']),
        ],
      );
      final args = f.toQuery().toArgs();
      expect(args['forms'], ['A']);
      expect(args['groups'], [
        {'form': 'A', 'conditions': <Object>[]},
      ]);
      expect(
        InboxFilter(
          blocks: [InboxBlock()],
        ).toQuery().toArgs().containsKey('groups'),
        isFalse,
      );
    });

    test(
      'the Outlook-style lines are sent only when chosen; days only when they are days',
      () {
        final a = const InboxFilter(
          forms: ['A', 'B'],
          createdBy: ['me'],
          status: 'closed',
        ).toQuery().toArgs();
        expect(a['forms'], ['A', 'B']);
        expect(a['createdBy'], ['me']);
        expect(a['status'], 'closed');
        expect(a.containsKey('sentBy'), isFalse);
        expect(
          const InboxFilter(
            taggedTo: ['me', 'sana'],
          ).toQuery().toArgs()['taggedTo'],
          ['me', 'sana'],
        );
        final d = const InboxFilter(
          from: '2026-11-01',
          to: '2026-11-23',
        ).toQuery().toArgs();
        expect([d['from'], d['to']], ['2026-11-01', '2026-11-23']);
        final bad = const InboxFilter(from: 'yesterday').toQuery().toArgs();
        expect(
          bad.containsKey('from'),
          isFalse,
          reason: 'a day that is not a day is not sent',
        );
      },
    );

    test('names: at most 50 of 1 to 200 characters', () {
      final f = InboxFilter(
        createdBy: [for (var i = 0; i < 80; i++) 'u$i', '', 'x' * 300],
      );
      expect((f.toQuery().toArgs()['createdBy'] as List).length, 50);
      expect(inboxNames(['a', 5, '', 'x' * 300, 'b']), ['a', 'b']);
      expect(inboxNames('no'), isEmpty);
    });
  });

  group('Search in', () {
    List<Map<String, dynamic>> views(
      List<String> w, {
      InboxFilter? f,
      List<String> team = const [],
    }) => (f ?? InboxFilter.none).copyWith(wheres: w).serverViews(team);

    test(
      'each entry is lines for the server; approvals and reminders are not',
      () {
        expect(views([]), [
          <String, dynamic>{},
        ], reason: 'none is every record');
        expect(views(['me']), [
          {
            'scope': ['me'],
          },
        ]);
        expect(views(['team']), [
          {
            'scope': ['team'],
          },
        ]);
        expect(
          views(['completed'], f: const InboxFilter(status: 'open')),
          [
            {'status': 'closed'},
          ],
          reason: 'Completed is the closed records, and wins over Open only',
        );
        expect(views(['requests'], team: ['ravi', 'sana']), [
          {
            'createdBy': ['me', 'ravi', 'sana'],
          },
        ]);
        expect(
          views(
            ['requests'],
            f: const InboxFilter(createdBy: ['ravi']),
            team: ['sana'],
          ),
          [<String, dynamic>{}],
          reason: 'a person chosen is the one asked',
        );
        final names = [for (var i = 0; i < 80; i++) 'u$i'];
        expect(
          (views(['requests'], team: names).single['createdBy'] as List).length,
          50,
          reason: 'me and the first 49 reports',
        );
        expect(views(['me', 'requests', 'completed'], team: ['r']), [
          {
            'scope': ['me'],
          },
          {
            'createdBy': ['me', 'r'],
          },
          {'status': 'closed'},
        ]);
        expect(views(['escalations']), [
          {
            'escalated': {'days': 3},
          },
        ]);
        expect(views(['approvals', 'approved', 'reminders']), isEmpty);
        expect(views(['approved', 'team']), [
          {
            'scope': ['team'],
          },
        ]);
        expect(views(['all', 'me']), [
          <String, dynamic>{},
        ], reason: 'All covers the rest');
      },
    );

    test(
      'several entries are several views, and an empty view is not sent',
      () {
        final q = const InboxFilter(
          wheres: ['me', 'completed'],
        ).toQuery().toArgs();
        expect(q['views'], [
          {
            'scope': ['me'],
          },
          {'status': 'closed'},
        ]);
        expect(
          q.containsKey('scope'),
          isFalse,
          reason: 'the entries are the scope',
        );
        expect(const InboxFilter().toQuery(scope: 'team').toArgs()['scope'], [
          'team',
        ]);
        expect(
          InboxQuery(views: const [{}]).toArgs().containsKey('views'),
          isFalse,
          reason: 'one empty view is no views',
        );
      },
    );

    test('the choice: only known entries, each once; Timeline alone', () {
      expect(InboxWhere.choice([], ['me', 'team', 'me', 'hack']), [
        'me',
        'team',
      ]);
      expect(InboxWhere.choice(['me'], ['me', 'timeline']), ['timeline']);
      expect(InboxWhere.choice(['timeline'], ['timeline', 'me']), ['me']);
      expect(InboxWhere.choice(['timeline'], ['timeline']), ['timeline']);
      expect(InboxWhere.choice(['me'], []), isEmpty);
    });

    test(
      'the panel offers Me, My Team, Requests, Completed, Escalations, Timeline; the model holds the rest',
      () {
        expect(InboxWhere.offered, [
          'me',
          'team',
          'requests',
          'completed',
          'escalations',
          'timeline',
        ]);
        expect(
          InboxWhere.known,
          containsAll(['approvals', 'approved', 'rejected', 'reminders']),
        );
      },
    );
  });

  group('facets', () {
    test(
      'ask under the panel as it stands, the forms ticked included, no blocks, limit 1',
      () {
        final f = InboxFilter(
          wheres: const ['team'],
          forms: const ['X'],
          sentTo: const ['ravi'],
          status: 'open',
          from: '2026-11-01',
          blocks: [
            InboxBlock(forms: ['Z']),
          ],
        );
        final a = f.toFacetQuery().toArgs(limit: 1);
        expect(a['facets'], isTrue);
        expect(a['forms'], ['X']);
        expect(a['views'], [
          {
            'scope': ['team'],
          },
        ]);
        expect(a['sentTo'], ['ravi']);
        expect(a['status'], 'open');
        expect(a['from'], '2026-11-01');
        expect(a.containsKey('groups'), isFalse);
        expect([a['limit'], a['offset']], [1, 0]);
        expect(
          const InboxFilter(
            wheres: ['completed'],
          ).toFacetQuery().toArgs(limit: 1)['views'],
          [
            {'status': 'closed'},
          ],
        );
        expect(
          const InboxFilter(
            wheres: ['requests'],
          ).toFacetQuery(team: ['ravi']).toArgs(limit: 1)['views'],
          [
            {
              'createdBy': ['me', 'ravi'],
            },
          ],
        );
        expect(
          const InboxFilter(
            wheres: ['escalations', 'me'],
          ).toFacetQuery().toArgs(limit: 1)['views'],
          [
            {
              'escalated': {'days': 3},
            },
            {
              'scope': ['me'],
            },
          ],
        );
        expect(
          const InboxFilter()
              .toFacetQuery()
              .toArgs(limit: 1)
              .containsKey('views'),
          isFalse,
        );
      },
    );

    test('the answer is read tolerantly', () {
      final r = InboxFacets.parse({
        'formCounts': {'A': 2, 'B': 0, '': 3, 'C': 'x', 'D': 1},
        'people': {
          'createdBy': ['me', 5, '', 'ravi'],
          'sentTo': 'no',
        },
      });
      expect(r.forms, {'A': 2, 'D': 1});
      expect(r.peopleOf('createdBy'), ['me', 'ravi']);
      expect(r.peopleOf('sentTo'), isEmpty);
      expect(r.peopleOf('taggedTo'), isEmpty);
      expect(InboxFacets.parse({}).forms, isEmpty);
    });

    test(
      'people lists start with Me, then each person once; a listed answer is exactly who is there',
      () {
        String up(String u) => u.toUpperCase();
        expect(
          [
            for (final c in inboxPeopleChoices([
              'ravi',
              'sana',
              'ravi',
              '',
              'me',
            ], up))
              (c.id, c.label),
          ],
          [('me', 'Me'), ('ravi', 'RAVI'), ('sana', 'SANA')],
        );
        expect([for (final c in inboxPeopleChoices([], up)) c.id], ['me']);
        expect(
          [
            for (final c in inboxPeopleChoices(
              ['ravi', 'me', 'ravi'],
              up,
              isListed: true,
            ))
              c.id,
          ],
          ['me', 'ravi'],
        );
        expect(
          [
            for (final c in inboxPeopleChoices(['ravi'], up, isListed: true))
              c.id,
          ],
          ['ravi'],
        );
        expect(inboxPeopleChoices([], up, isListed: true), isEmpty);
      },
    );
  });

  group('filterCount', () {
    test('counts the lines that say something', () {
      expect(const InboxFilter().filterCount(), 0);
      expect(const InboxFilter(wheres: ['me']).filterCount(), 1);
      expect(const InboxFilter(wheres: ['me']).filterCount(baseWhere: 'me'), 0);
      expect(
        const InboxFilter(wheres: ['team']).filterCount(baseWhere: 'me'),
        1,
      );
      expect(
        const InboxFilter(wheres: ['me', 'team']).filterCount(baseWhere: 'me'),
        1,
      );
      expect(const InboxFilter(forms: ['A']).filterCount(), 1);
      expect(
        const InboxFilter(
          createdBy: ['me'],
          sentBy: ['a'],
          sentTo: ['b'],
          taggedTo: ['c'],
        ).filterCount(),
        4,
      );
      expect(
        const InboxFilter(from: '2026-11-01', to: '2026-11-02').filterCount(),
        1,
        reason: 'the dates are one line',
      );
      expect(const InboxFilter(status: 'open').filterCount(), 1);
      expect(const InboxFilter(sort: 'asc').filterCount(), 1);
      expect(
        InboxFilter(
          blocks: [
            InboxBlock(forms: ['A']),
            InboxBlock(),
            InboxBlock(sentTo: ['x']),
          ],
        ).filterCount(),
        2,
      );
      expect(
        InboxFilter(
          wheres: const ['requests'],
          forms: const ['A'],
          createdBy: const ['me'],
          from: '2026-11-01',
          sort: 'desc',
          status: 'closed',
          blocks: [
            InboxBlock(forms: ['A']),
          ],
        ).filterCount(),
        7,
      );
    });

    test(
      'Sort: Open only and Closed only are the status; an order clears it',
      () {
        var f = const InboxFilter(sort: 'asc').withSortChoice('open');
        expect([f.sort, f.status, f.sortChoice], ['latest', 'open', 'open']);
        f = f.withSortChoice('desc');
        expect([f.sort, f.status, f.sortChoice], ['desc', '', 'desc']);
        f = f.withSortChoice('closed');
        expect(f.status, 'closed');
        expect(f.withSortChoice('nonsense').sort, 'latest');
      },
    );
  });

  group('saved-view shape', () {
    test('round-trips through the web keys', () {
      final f = InboxFilter(
        wheres: const ['me', 'completed'],
        forms: const ['A'],
        createdBy: const ['ravi'],
        from: '2026-11-01',
        sort: 'oldest',
        status: 'open',
        blocks: [
          InboxBlock(
            id: 'q1',
            forms: ['A'],
            conditions: [cond('t', value: 'x')],
          ),
        ],
      );
      final setup = f.toSetup();
      expect(
        setup.keys,
        containsAll([
          'folder',
          'wheres',
          'dataForms',
          'filters',
          'sort',
          'timing',
          'blocks',
        ]),
      );
      final back = InboxFilter.fromSetup(setup);
      expect(back.wheres, ['me', 'completed']);
      expect(back.forms, ['A']);
      expect(back.createdBy, ['ravi']);
      expect(back.from, '2026-11-01');
      expect(back.sort, 'oldest');
      expect(back.status, 'open');
      expect(back.blocks.single.conditions.single.value, 'x');
      expect(const InboxFilter(wheres: ['me']).toSetup()['scopePick'], ['me']);
      expect(
        InboxFilter.fromSetup(
          const InboxFilter(wheres: ['team']).toSetup(),
        ).wheres,
        ['team'],
      );
      expect(
        InboxFilter.fromSetup(
          const InboxFilter(wheres: ['requests']).toSetup(),
        ).wheres,
        ['requests'],
      );
      expect(InboxFilter.fromSetup('x').isActive(), isFalse);
      expect(
        InboxFilter.fromSetup({
          'sort': 'bad',
          'filters': 5,
          'timing': {'from': 'x'},
        }).sort,
        'latest',
      );
    });
  });

  group('sort', () {
    test(
      'Latest and Oldest go by time; a row with no time goes last either way',
      () {
        final rows = [
          row('a', 'a', 20),
          row('b', 'b', 10),
          row('c', 'c', 0),
          row('d', 'd', 30),
          row('e', 'e', 0),
        ];
        expect(subjects(sortInboxRows(rows, 'latest')), [
          'd',
          'a',
          'b',
          'c',
          'e',
        ]);
        expect(subjects(sortInboxRows(rows, 'oldest')), [
          'b',
          'a',
          'd',
          'c',
          'e',
        ]);
        expect(subjects(sortInboxRows(rows, 'nonsense')), [
          'd',
          'a',
          'b',
          'c',
          'e',
        ]);
        expect(subjects(rows), [
          'a',
          'b',
          'c',
          'd',
          'e',
        ], reason: 'the list given is never changed');
        expect(sortInboxRows([], 'asc'), isEmpty);
      },
    );

    test(
      'A to Z and Z to A go by the words: numbers as numbers, case and accents ignored, ties newest first',
      () {
        final rows = [
          row('a', 'Ticket 10', 1),
          row('b', 'ticket 2', 2),
          row('c', 'Émile', 3),
          row('d', 'banana', 4),
          row('e', 'Apple', 5),
          row('f', 'apple', 9),
          row('g', '', 7),
        ];
        expect(subjects(sortInboxRows(rows, 'asc')), [
          '',
          'apple',
          'Apple',
          'banana',
          'Émile',
          'ticket 2',
          'Ticket 10',
        ]);
        expect(subjects(sortInboxRows(rows, 'desc')), [
          'Ticket 10',
          'ticket 2',
          'Émile',
          'banana',
          'apple',
          'Apple',
          '',
        ]);
      },
    );
  });
}
