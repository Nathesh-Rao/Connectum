import 'dart:async';

import 'package:connectum/core/widgets/app_state_view.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/inbox_filter_controller.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

Map<String, dynamic> facetReply({
  Map<String, int> forms = const {'t': 2},
  Map<String, List<String>> people = const {},
}) => {
  'submissions': <Object>[],
  'structures': <String, Object>{},
  'total': 0,
  'formCounts': forms,
  'people': people,
};

bool isFacet(Map<String, dynamic> a) => a['facets'] == true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  late InboxController c;
  final panels = <InboxFilterController>[];

  /// A rig whose list answers records and whose facets answer [facets].
  Future<InboxController> start({
    Map<String, dynamic> Function(Map<String, dynamic>)? facets,
    int reports = 0,
  }) async {
    rig = InboxRig();
    addTearDown(() {
      for (final p in panels) {
        p.onClose();
      }
      panels.clear();
      rig.dispose();
    });
    rig.routes['records.counts'] = (_) => countsReply(reports: reports);
    rig.routes['records.query'] = (a) => isFacet(a)
        ? (facets ?? (_) => facetReply())(a)
        : queryReply([record(2), record(1)]);
    rig.routes['records.people'] = (_) => {
      'team': ['rhea', 'ravi'],
      'sentBy': ['sana'],
      'sentTo': ['ravi'],
    };
    c = rig.controller..onInit();
    await settle();
    return c;
  }

  InboxFilterController open({String base = 'me', bool isTeam = false}) {
    final p = InboxFilterController(
      inbox: rig.inbox,
      initial: c.filter.value,
      baseWhere: base,
      isTeamShown: isTeam,
      forms: const {'t': 'Thing', 'u': 'Other'},
      onApply: c.applyFilter,
      onClear: c.clearFilter,
      wait: const Duration(milliseconds: 1),
    )..onInit();
    panels.add(p);
    return p;
  }

  Future<void> wait() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await settle();
  }

  List<Map<String, dynamic>> facetAsks() => [
    for (final a in rig.argsOf('records.query'))
      if (isFacet(a)) a,
  ];

  List<Map<String, dynamic>> listAsks() => [
    for (final a in rig.argsOf('records.query'))
      if (!isFacet(a)) a,
  ];

  group('apply, dismiss, clear', () {
    test(
      'Apply sends the filtered records.query from page one and shows it',
      () async {
        await start();
        final p = open();
        p.setForms(['t']);
        p.setPeople('createdBy', ['me']);
        p.setFrom('2026-11-01');
        p.setSortChoice('closed');
        p.apply();
        await settle();
        final a = listAsks().last;
        expect(a['forms'], ['t']);
        expect(a['createdBy'], ['me']);
        expect(a['from'], '2026-11-01');
        expect(a['status'], 'closed');
        expect(a['scope'], ['me'], reason: 'Search in held only the switch');
        expect(a['offset'], 0);
        expect(c.filterCount, 4);
        expect(c.viewState.value, AppViewState.content);
      },
    );

    test('Search in with other entries sends views, not the switch', () async {
      await start();
      final p = open();
      p.setWheres(['me', 'completed', 'escalations']);
      p.apply();
      await settle();
      final a = listAsks().last;
      expect(a.containsKey('scope'), isFalse);
      expect(a['views'], [
        {
          'scope': ['me'],
        },
        {'status': 'closed'},
        {
          'escalated': {'days': 3},
        },
      ]);
      expect(c.filter.value.wheres.length, 3);
    });

    test('only Me or only My Team is the switch', () async {
      await start(reports: 2);
      final p = open(isTeam: true);
      p.setWheres(['team']);
      p.apply();
      await settle();
      expect(c.scope.value, InboxScope.team);
      expect(c.filter.value.wheres, isEmpty);
      expect(listAsks().last['scope'], ['team']);
      expect(c.filterCount, 0);
    });

    test(
      'Requests asks the reports (records.people) and sends me + the first 49',
      () async {
        await start();
        rig.routes['records.people'] = (_) => {
          'team': [for (var i = 0; i < 80; i++) 'u$i'],
        };
        final p = open();
        p.setWheres(['requests']);
        p.apply();
        await settle();
        final v = listAsks().last['views'] as List;
        final names = (v.single as Map)['createdBy'] as List;
        expect(names.length, 50);
        expect(names.first, 'me');
      },
    );

    test(
      'dismissing without Apply drops the draft: nothing changes, no new list read',
      () async {
        await start();
        final before = listAsks().length;
        final p = open();
        p.setForms(['t']);
        p.setWheres(['requests']);
        await wait();
        p.onClose();
        await wait();
        expect(c.filter.value.isActive(), isFalse);
        expect(c.filterCount, 0);
        expect(listAsks().length, before);
      },
    );

    test(
      'Clear puts everything back: no filter, the switch on Me, an unfiltered read',
      () async {
        await start(reports: 2);
        c.applyFilter(
          const InboxFilter(wheres: ['team'], forms: ['t'], sort: 'asc'),
        );
        await settle();
        expect(c.scope.value, InboxScope.team);
        final p = open(base: 'team', isTeam: true);
        p.clear();
        await settle();
        expect(c.filter.value.isActive(), isFalse);
        expect(c.scope.value, InboxScope.me);
        expect(listAsks().last, {
          'scope': ['me'],
          'limit': 100,
          'offset': 0,
          'withDetails': true,
          'fileMeta': 2,
        });
      },
    );

    test('Applying resets the list to page one', () async {
      await start();
      rig.routes['records.query'] = (a) => isFacet(a)
          ? facetReply()
          : queryReply([record(5), record(4)], total: 9, hasMore: true);
      await c.refreshList();
      await settle();
      c.applyFilter(const InboxFilter(forms: ['t']));
      await settle();
      expect(listAsks().last['offset'], 0);
      expect(c.page.value?.received, 2);
    });

    test(
      'the four orders sort what is loaded; the server is not asked',
      () async {
        await start();
        c.applyFilter(const InboxFilter(sort: 'oldest'));
        await settle();
        expect(rig.ids, [1, 2]);
        expect(listAsks().last.containsKey('sort'), isFalse);
      },
    );
  });

  group('empty texts', () {
    test('with a filter set', () async {
      await start();
      rig.routes['records.query'] = (_) => queryReply([]);
      c.applyFilter(const InboxFilter(forms: ['t']));
      await settle();
      expect(c.viewState.value, AppViewState.empty);
      expect(c.emptyText, 'No records match the filter.');
    });

    test('with nothing set', () async {
      await start();
      rig.routes['records.query'] = (_) => queryReply([]);
      await c.refreshList();
      await settle();
      expect(c.viewState.value, AppViewState.empty);
      expect(c.emptyText, 'No records yet.');
    });

    test('the capped note stays', () async {
      await start();
      rig.routes['records.query'] = (_) =>
          queryReply([record(1)], total: 1001, capped: true);
      c.applyFilter(const InboxFilter(forms: ['t']));
      await settle();
      expect(c.totalLabel, '1000+ records');
    });
  });

  group('facets', () {
    test('are not read when the Inbox opens', () async {
      await start();
      expect(facetAsks(), isEmpty);
      expect(rig.asked, isNot(contains('records.people')));
    });

    test(
      'are read while the panel is open, one ask for a burst of changes, 150 ms by default',
      () async {
        await start(
          facets: (_) => facetReply(
            people: {
              'sentBy': ['sana', 'ravi'],
            },
          ),
        );
        expect(
          InboxFilterController(
            inbox: rig.inbox,
            initial: InboxFilter.none,
            baseWhere: 'me',
            isTeamShown: false,
            forms: const {},
            onApply: (_) {},
            onClear: () {},
          ).wait,
          const Duration(milliseconds: 150),
        );
        final p = open();
        p.setPeople('sentBy', ['sana']);
        p.setPeople('sentBy', ['sana', 'ravi']);
        p.setFrom('2026-11-01');
        await wait();
        expect(facetAsks().length, 1);
        final a = facetAsks().single;
        expect(a['facets'], isTrue);
        expect([a['limit'], a['offset']], [1, 0]);
        expect(a['sentBy'], ['sana', 'ravi']);
        expect(a['from'], '2026-11-01');
        expect(a['views'], [
          {
            'scope': ['me'],
          },
        ]);
        expect(a.containsKey('groups'), isFalse);
      },
    );

    test(
      'Data lists only forms that have records, with counts; people are who is on them, Me first',
      () async {
        await start(
          facets: (_) => facetReply(
            forms: {'t': 2, 'u': 0, 'zeta': 1},
            people: {
              'createdBy': ['ravi', 'me'],
              'sentBy': ['sana'],
            },
          ),
        );
        final p = open();
        await wait();
        expect(
          [for (final f in p.formChoices) (f.id, f.label)],
          [('t', 'Thing (2)'), ('zeta', 'zeta (1)')],
        );
        expect(
          [for (final x in p.peopleChoices('createdBy')) x.id],
          ['me', 'ravi'],
        );
        expect([for (final x in p.peopleChoices('sentBy')) x.id], ['sana']);
        expect(p.peopleChoices('sentTo'), isEmpty);
        expect(p.isFresh, isTrue);
      },
    );

    test('while counting nothing is offered and the text says so', () async {
      final held = Completer<Map<String, dynamic>>();
      await start(facets: (_) => throw UnimplementedError());
      rig.routes['records.query'] = (a) =>
          isFacet(a) ? held.future : queryReply([record(1)]);
      final p = open();
      await wait();
      expect(p.formChoices, isEmpty);
      expect(p.formsEmptyText, 'Counting the forms...');
      held.complete(facetReply());
      await wait();
      expect(p.formChoices, isNotEmpty);
    });

    test('an answer for another Search in is never shown', () async {
      final held = <Completer<Map<String, dynamic>>>[];
      await start();
      rig.routes['records.query'] = (a) {
        if (!isFacet(a)) return queryReply([record(1)]);
        final h = Completer<Map<String, dynamic>>();
        held.add(h);
        return h.future;
      };
      final p = open();
      await wait();
      expect(held.length, 1);
      held[0].complete(facetReply(forms: {'t': 5}));
      await wait();
      expect(p.formChoices.single.label, 'Thing (5)');
      p.setWheres(['completed']);
      await wait();
      expect(held.length, 2);
      expect(p.formChoices, isEmpty, reason: 'the old answer is of group "me"');
      expect(p.formsEmptyText, 'Counting the forms...');
      held[1].complete(facetReply(forms: {'u': 1}));
      await wait();
      expect([for (final f in p.formChoices) f.label], ['Other (1)']);
    });

    test(
      'an old answer of the same Search in is dropped when a newer ask is on its way',
      () async {
        final held = <Completer<Map<String, dynamic>>>[];
        await start();
        rig.routes['records.query'] = (a) {
          if (!isFacet(a)) return queryReply([record(1)]);
          final h = Completer<Map<String, dynamic>>();
          held.add(h);
          return h.future;
        };
        final p = open();
        await wait();
        p.setPeople('createdBy', ['me']);
        await wait();
        expect(held.length, 1, reason: 'the gate runs one read at a time');
        held[0].complete(facetReply(forms: {'t': 99}));
        await wait();
        expect(p.formChoices, isEmpty, reason: 'a replaced ask is never shown');
        expect(held.length, 2);
        held[1].complete(facetReply(forms: {'t': 1}));
        await wait();
        expect(p.formChoices.single.label, 'Thing (1)');
      },
    );

    test('when they cannot be counted every form is offered', () async {
      await start(facets: (_) => throw const SocketCallError('server_error'));
      final p = open();
      await wait();
      expect(p.hasFailed.value, isTrue);
      expect([for (final f in p.formChoices) f.label], ['Other', 'Thing']);
      expect(p.formsEmptyText, 'No forms to choose from yet.');
    });

    test(
      'a chosen form or person that has no record here any more is dropped',
      () async {
        var phase = 0;
        await start(
          facets: (_) => phase == 0
              ? facetReply(
                  forms: {'t': 2, 'u': 1},
                  people: {
                    'createdBy': ['me', 'ravi'],
                  },
                )
              : facetReply(
                  forms: {'t': 2},
                  people: {
                    'createdBy': ['me'],
                  },
                ),
        );
        final p = open();
        await wait();
        p.setForms(['t', 'u']);
        p.setPeople('createdBy', ['me', 'ravi']);
        await wait();
        expect(p.draft.value.forms, ['t', 'u']);
        expect(p.draft.value.createdBy, ['me', 'ravi']);
        phase = 1;
        p.setFrom('2026-11-01');
        await wait();
        expect(p.draft.value.forms, ['t']);
        expect(p.draft.value.createdBy, ['me']);
      },
    );

    test(
      'an approvals-only choice asks no facets (they are not records)',
      () async {
        await start();
        final p = open();
        await wait();
        final before = facetAsks().length;
        p.draft.value = p.draft.value.copyWith(wheres: ['approvals']);
        await wait();
        expect(facetAsks().length, before);
        expect(p.isOnServer, isFalse);
      },
    );

    test('closing the panel stops the asks', () async {
      await start();
      final p = open();
      p.setForms(['t']);
      p.onClose();
      await wait();
      expect(facetAsks(), isEmpty);
    });

    test(
      'My Team is offered only with reports; the panel offers the entries with Timeline last',
      () async {
        await start();
        expect(
          [for (final x in open().searchInChoices) x.id],
          [
            'me',
            'requests',
            'allapprovals',
            'approvals',
            'approved',
            'rejected',
            'completed',
            'escalations',
            'timeline',
          ],
        );
        expect(
          [for (final x in open(isTeam: true).searchInChoices) x.id],
          [
            'me',
            'team',
            'requests',
            'allapprovals',
            'approvals',
            'approved',
            'rejected',
            'completed',
            'escalations',
            'timeline',
          ],
        );
      },
    );
  });
}
