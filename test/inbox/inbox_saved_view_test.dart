import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_saved_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// A view as the web saves it: keys the phone does not model, and a timing
/// with a period and hours.
Map<String, dynamic> webView() => {
  'folder': 'task',
  'lens': 'team',
  'kinds': ['broadcast'],
  'dataForms': ['Tickets'],
  'approvalPick': ['pending'],
  'scopePick': ['me'],
  'wheres': <String>[],
  'teamMembers': ['ravi'],
  'blocks': [
    {
      'id': 'q1',
      'forms': ['Tickets'],
      'createdBy': ['me'],
      'sentBy': <String>[],
      'sentTo': <String>[],
      'conditions': <dynamic>[],
    },
  ],
  'filters': {
    'forms': ['Tickets'],
    'createdBy': <String>[],
    'sentBy': <String>[],
    'sentTo': <String>[],
    'taggedTo': <String>[],
    'status': 'open',
  },
  'sort': 'oldest',
  'timing': {
    'period': 'week',
    'from': '',
    'to': '',
    'hours': [0, 1440],
  },
};

InboxFilter read(Object? v) => InboxSetup.restore(v).filter;

void main() {
  group('restore (restoreOf)', () {
    test(
      'a view that is missing, damaged or from another version never throws',
      () {
        for (final bad in [
          null,
          'x',
          5,
          <dynamic>[],
          <String, dynamic>{},
          {
            'folder': 'nope',
            'lens': 7,
            'kinds': 'x',
            'dataForms': [1, null],
            'teamMembers': <String, dynamic>{},
            'blocks': 'x',
            'sort': 'weird',
            'timing': 'x',
            'filters': 'x',
          },
        ]) {
          final r = InboxSetup.restore(bad);
          expect(r.filter.wheres, isEmpty, reason: '$bad');
          expect(r.filter.sort, InboxSort.latest);
          expect(r.filter.blocks, isEmpty);
          expect(r.filter.from, '');
          expect(r.scope, 'me');
        }
      },
    );

    test(
      'an unknown folder or "all" is the plain list, a known one is its entry',
      () {
        expect(read({'folder': 'nope'}).wheres, isEmpty);
        expect(read({'folder': 'all'}).wheres, isEmpty);
        expect(read({'folder': 'data'}).wheres, isEmpty);
        expect(read({'folder': 'requests'}).wheres, ['requests']);
        expect(read({'folder': 'approval'}).wheres, ['approvals']);
        expect(read({'folder': 'escalation'}).wheres, ['escalations']);
      },
    );

    test(
      'wheres count only with more than one entry, known, each once, never Timeline',
      () {
        expect(
          read({
            'wheres': ['me', 'requests', 'me', 'hack', 'timeline'],
          }).wheres,
          ['me', 'requests'],
        );
        expect(
          read({
            'wheres': ['me'],
          }).wheres,
          isEmpty,
        );
        expect(read({'wheres': 'me'}).wheres, isEmpty);
      },
    );

    test('scopePick counts only when exactly one of me / team', () {
      expect(
        InboxSetup.restore({
          'scopePick': ['me'],
        }).scope,
        'me',
      );
      expect(
        InboxSetup.restore({
          'scopePick': ['team'],
        }).scope,
        'team',
      );
      expect(
        InboxSetup.restore({
          'scopePick': ['team'],
        }, isTeamShown: false).scope,
        'me',
      );
      for (final v in [
        ['me', 'team'],
        ['hack'],
        'me',
        ['me', 'me', 'team'],
      ]) {
        final r = InboxSetup.restore({'scopePick': v});
        expect(r.scope, 'me', reason: '$v');
        expect(r.filter.wheres, isEmpty, reason: '$v');
      }
      // one entry of the switch is the switch, not a "Search in" line
      expect(
        InboxSetup.restore({
          'scopePick': ['team'],
        }).filter.wheres,
        isEmpty,
      );
    });

    test('filters and the day range come back checked', () {
      final f = read({
        'filters': {
          'forms': ['Tickets', 5],
          'createdBy': ['me'],
          'sentTo': ['ravi'],
          'taggedTo': ['sana'],
          'status': 'open',
        },
        'timing': {'from': '2026-11-01', 'to': 'soon'},
        'sort': 'asc',
      });
      expect(f.forms, ['Tickets']);
      expect(f.createdBy, ['me']);
      expect(f.sentTo, ['ravi']);
      expect(f.taggedTo, ['sana']);
      expect(f.status, 'open');
      expect(f.from, '2026-11-01');
      expect(f.to, '');
      expect(f.sort, 'asc');
      expect(
        read({
          'filters': {'status': 'weird'},
        }).status,
        '',
      );
    });

    test(
      'a web timing with period and hours opens (the days are all that is used)',
      () {
        final f = read(webView());
        expect(f.from, '');
        expect(f.to, '');
        expect(f.sort, 'oldest');
        expect(f.forms, ['Tickets']);
        expect(f.blocks.single.forms, ['Tickets']);
        expect(f.blocks.single.id, 'q1');
      },
    );
  });

  group('name rules (cleanName, nameTaken, MAX_VIEWS)', () {
    InboxSavedView v(String n) => InboxSavedView(name: n, setup: const {});

    test('clean: one line, trimmed, at most 40 characters', () {
      expect(InboxViewRules.clean('  My   view \n'), 'My view');
      expect(InboxViewRules.clean(null), '');
      expect(InboxViewRules.clean('a' * 60).length, 40);
      expect(InboxViewRules.clean('a\u0000b'), 'a b');
    });

    test('empty, reserved, taken and too many', () {
      final views = [v('One'), v('Two')];
      expect(
        InboxViewRules.problem('  ', views, isNew: true),
        InboxViewRules.empty,
      );
      expect(
        InboxViewRules.problem('default view', views, isNew: true),
        InboxViewRules.reserved,
      );
      expect(
        InboxViewRules.problem('one', views, isNew: true),
        InboxViewRules.taken,
      );
      expect(InboxViewRules.problem('Three', views, isNew: true), '');
      final full = [for (var i = 0; i < 20; i++) v('V$i')];
      expect(
        InboxViewRules.problem('New', full, isNew: true),
        InboxViewRules.tooMany,
      );
      expect(InboxViewRules.problem('V3', full, isNew: false), '');
      expect(
        InboxViewRules.problem('Brand new', full, isNew: false),
        InboxViewRules.tooMany,
      );
    });

    test('saving over the open Default View is allowed', () {
      expect(
        InboxViewRules.problem(InboxViewLimits.defaultName, [
          v('Default View'),
        ], isNew: false),
        '',
      );
    });
  });

  group('setup key (setupKey)', () {
    String key(
      InboxFilter f, [
      String scope = 'me',
      Map<String, dynamic> base = const {},
    ]) => InboxSetup.keyOf(InboxSetup.compose(base, f, scope));

    test('equal setups have equal keys, whatever the order of the keys', () {
      expect(key(InboxFilter.none), key(const InboxFilter()));
      expect(
        InboxSetup.keyOf({
          'b': 1,
          'a': {'d': 1, 'c': 2},
        }),
        InboxSetup.keyOf({
          'a': {'c': 2, 'd': 1},
          'b': 1,
        }),
      );
    });

    test('a change of any modelled piece changes the key', () {
      final plain = key(InboxFilter.none);
      expect(key(const InboxFilter(sort: 'oldest')), isNot(plain));
      expect(key(const InboxFilter(forms: ['A'])), isNot(plain));
      expect(key(const InboxFilter(status: 'open')), isNot(plain));
      expect(key(const InboxFilter(from: '2026-11-01')), isNot(plain));
      expect(key(const InboxFilter(wheres: ['requests'])), isNot(plain));
      expect(key(const InboxFilter(wheres: ['me', 'requests'])), isNot(plain));
      expect(key(InboxFilter.none, 'team'), isNot(plain));
      expect(
        key(
          InboxFilter(
            blocks: [
              InboxBlock(id: 'b', forms: const ['A']),
            ],
          ),
        ),
        isNot(plain),
      );
    });

    test('what is restored makes the very key it was saved with', () {
      final f = const InboxFilter(
        wheres: ['me', 'requests'],
        forms: ['A'],
        sort: 'asc',
        from: '2026-11-01',
        to: '2026-11-24',
        status: 'closed',
      );
      final saved = InboxSetup.compose(const {}, f, 'me');
      final r = InboxSetup.restore(saved);
      expect(
        InboxSetup.keyOf(InboxSetup.compose(saved, r.filter, r.scope)),
        InboxSetup.keyOf(saved),
      );
    });

    test('the plain list is the key of a screen nothing was set on', () {
      expect(InboxSetup.keyOf(InboxSetup.plain()), key(InboxFilter.none));
    });
  });

  group('compose keeps what the phone does not model', () {
    test('a web view opens, is changed, and keeps every key it came with', () {
      final saved = webView();
      final r = InboxSetup.restore(saved);
      final opened = InboxSetup.keyOf(
        InboxSetup.compose(saved, r.filter, r.scope),
      );
      // opened and not changed: the key is the same twice
      expect(
        opened,
        InboxSetup.keyOf(InboxSetup.compose(saved, r.filter, r.scope)),
      );

      final changed = InboxSetup.compose(
        saved,
        r.filter.copyWith(sort: 'desc'),
        r.scope,
      );
      expect(InboxSetup.keyOf(changed), isNot(opened));
      expect(changed['sort'], 'desc');
      expect(changed['folder'], 'task');
      expect(changed['lens'], 'team');
      expect(changed['kinds'], ['broadcast']);
      expect(changed['dataForms'], ['Tickets']);
      expect(changed['approvalPick'], ['pending']);
      expect(changed['teamMembers'], ['ravi']);
      expect(changed['scopePick'], ['me']);
      expect(changed['timing'], {
        'period': 'week',
        'from': '',
        'to': '',
        'hours': [0, 1440],
      });
      expect(changed['filters'], containsPair('status', 'open'));
      expect((changed['blocks'] as List).single, containsPair('id', 'q1'));
      expect(changed.keys.toSet().difference(InboxSetup.keys.toSet()), isEmpty);
    });

    test(
      'a new day range replaces the period of the web (the phone has no period)',
      () {
        final saved = webView();
        final r = InboxSetup.restore(saved);
        final changed = InboxSetup.compose(
          saved,
          r.filter.copyWith(from: '2026-11-01', to: '2026-11-24'),
          r.scope,
        );
        expect(changed['timing'], {'from': '2026-11-01', 'to': '2026-11-24'});
      },
    );

    test('a new view writes the day range as from and to only', () {
      final s = InboxSetup.compose(
        const {},
        const InboxFilter(from: '2026-11-01', to: '2026-11-24'),
        'me',
      );
      expect(s['timing'], {'from': '2026-11-01', 'to': '2026-11-24'});
      expect(s['folder'], 'data');
      expect(InboxViewLimits.maxName, 40);
    });

    test('the folder follows a "Search in" entry, a task folder stays', () {
      expect(
        InboxSetup.compose(
          const {},
          const InboxFilter(wheres: ['requests']),
          'me',
        )['folder'],
        'requests',
      );
      expect(
        InboxSetup.compose(
          {'folder': 'task'},
          const InboxFilter(wheres: ['requests']),
          'me',
        )['folder'],
        'requests',
      );
      expect(
        InboxSetup.compose(
          {'folder': 'broadcast'},
          InboxFilter.none,
          'me',
        )['folder'],
        'broadcast',
      );
    });

    test(
      'the switch on My Team is a scopePick of team; Me on a plain view is none',
      () {
        expect(
          InboxSetup.compose(const {}, InboxFilter.none, 'team')['scopePick'],
          ['team'],
        );
        expect(
          InboxSetup.compose(const {}, InboxFilter.none, 'me')['scopePick'],
          <String>[],
        );
      },
    );

    test('the saved view parses tolerantly and keeps unknown keys', () {
      final v = InboxSavedView.tryParse({
        'name': 'Mine',
        'view': {'folder': 'data', 'future': 1, 5: 'x'},
        'savedTs': 12.0,
      })!;
      expect(v.setup['future'], 1);
      expect(v.savedTs, 12);
      expect(InboxSavedView.tryParse({'name': 'x', 'view': 'no'}), isNull);
      expect(InboxSavedView.tryParse({'name': '', 'view': {}}), isNull);
      expect(InboxSavedView.tryParse('x'), isNull);
      final list = InboxViewList.tryParse({
        'views': [
          {'name': 'A', 'view': <String, dynamic>{}},
          'junk',
          {'name': 'B'},
        ],
        'default': 7,
      })!;
      expect(list.views.map((v) => v.name), ['A']);
      expect(list.defaultName, isNull);
      expect(InboxViewList.tryParse({'x': 1}), isNull);
    });
  });
}
