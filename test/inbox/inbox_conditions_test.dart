import 'package:connectum/data/repositories/inbox_field_kinds.dart';
import 'package:connectum/data/socket/socket_service.dart';
import 'package:connectum/features/inbox/inbox_controller.dart';
import 'package:connectum/features/inbox/inbox_filter_controller.dart';
import 'package:connectum/features/inbox/models/inbox_filter.dart';
import 'package:connectum/features/inbox/models/inbox_page.dart';
import 'package:connectum/features/inbox/models/inbox_query.dart';
import 'package:connectum/features/inbox/models/inbox_row.dart';
import 'package:connectum/features/inbox/models/inbox_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inbox_screen_support.dart';
import 'inbox_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InboxRig rig;
  late InboxController c;
  final panels = <InboxFilterController>[];
  var sourceReply = sourcesReply;
  var isSourceDown = false;

  Future<void> start() async {
    rig = InboxRig();
    sourceReply = sourcesReply;
    isSourceDown = false;
    addTearDown(() {
      for (final p in panels) {
        p.onClose();
      }
      panels.clear();
      rig.dispose();
    });
    rig.routes['ai.enterprise'] = (_) {
      if (isSourceDown) throw const SocketCallError('server_error');
      return sourceReply();
    };
    rig.routes['records.query'] = (a) => a['facets'] == true
        ? {
            'submissions': <Object>[],
            'structures': <String, Object>{},
            'total': 0,
            'formCounts': {'t': 2, 'u': 1},
          }
        : queryReply([record(2), record(1)]);
    rig.routes['records.people'] = (_) => {
      'team': <String>[],
      'sentBy': <String>[],
      'sentTo': <String>[],
    };
    c = rig.controller..onInit();
    await settle();
  }

  InboxFilterController open({InboxFilter? initial}) {
    final p = InboxFilterController(
      inbox: rig.inbox,
      initial: initial ?? c.filter.value,
      baseWhere: 'me',
      isTeamShown: false,
      forms: const {'t': 'Thing', 'u': 'Other'},
      onApply: c.applyFilter,
      onClear: c.clearFilter,
      fieldKinds: rig.fieldKinds,
      wait: const Duration(milliseconds: 1),
    )..onInit();
    panels.add(p);
    return p;
  }

  int sourceReads() => rig.argsOf('ai.enterprise').length;

  /// A panel with the Advanced fold open on one block of form [forms].
  Future<(InboxFilterController, String)> withBlock(List<String> forms) async {
    final p = open();
    p.toggleAdvanced();
    final id = p.draft.value.blocks.single.id;
    p.setBlockForms(id, forms);
    await settle();
    return (p, id);
  }

  InboxBlock blockOf(InboxFilterController p, String id) =>
      p.draft.value.blocks.firstWhere((b) => b.id == id);

  group('the field kind provider', () {
    test('nothing is read until the Advanced fold is open and a block has '
        'exactly one form', () async {
      await start();
      final p = open();
      await settle();
      expect(sourceReads(), 0, reason: 'fold closed');
      p.toggleAdvanced();
      await settle();
      expect(sourceReads(), 0, reason: 'a block with no form');
      p.setBlockForms(p.draft.value.blocks.single.id, ['t', 'u']);
      await settle();
      expect(sourceReads(), 0, reason: 'two forms');
      p.setBlockForms(p.draft.value.blocks.single.id, ['t']);
      await settle();
      expect(sourceReads(), 1);
      expect(p.kindsState.value, InboxKindsState.ready);
    });

    test(
      'the read is kept for the session: a second panel reads nothing',
      () async {
        await start();
        final (p, id) = await withBlock(['t']);
        expect(sourceReads(), 1);
        p.setBlockForms(id, ['u']);
        p.setBlockForms(id, ['t']);
        await settle();
        expect(sourceReads(), 1);
        final q = open();
        q.toggleAdvanced();
        q.setBlockForms(q.draft.value.blocks.single.id, ['t']);
        await settle();
        expect(sourceReads(), 1, reason: 'cached in memory');
        expect(q.kindsState.value, InboxKindsState.ready);
      },
    );

    test('asks for the forms only, through the one gate', () async {
      await start();
      await withBlock(['t']);
      expect(rig.argsOf('ai.enterprise').single, {'what': 'forms'});
    });

    test(
      'field kinds follow the column type: number, date, bool, else text',
      () async {
        await start();
        final (p, id) = await withBlock(['t']);
        final k = rig.fieldKinds;
        expect(k.kindOf('t', 'hours'), 'number');
        expect(k.kindOf('t', 'count'), 'number');
        expect(k.kindOf('t', 'due'), 'date');
        expect(k.kindOf('t', 'ok'), 'bool');
        expect(k.kindOf('t', 'pick'), 'text');
        expect(k.kindOf('t', 'nope'), 'text');
        expect(k.kindOf('T', 'hours'), 'number', reason: 'form id any case');
        expect(k.fieldsOf('zzz'), isEmpty);
        expect(
          [for (final f in p.fieldChoices(blockOf(p, id))) f.label],
          ['Title', 'Hours', 'Count', 'Due date', 'Approved', 'Pick'],
          reason: 'captions come from the form definition',
        );
      },
    );

    test('a failed read says so, the block still works, and a new form tries '
        'again', () async {
      await start();
      isSourceDown = true;
      final (p, id) = await withBlock(['t']);
      expect(p.kindsState.value, InboxKindsState.failed);
      expect(
        InboxFilterController.conditionsUnavailableText,
        'Conditions are not available right now',
      );
      expect(p.canAddCondition(blockOf(p, id)), isFalse);
      p.changeBlock(id, (b) => b.copyWith(createdBy: ['me']));
      expect(p.draft.value.groups.single, {
        'form': 't',
        'createdBy': ['me'],
        'conditions': <Object>[],
      });
      isSourceDown = false;
      p.setBlockForms(id, ['t']);
      await settle();
      expect(p.kindsState.value, InboxKindsState.ready);
    });

    test('a panel with no provider says conditions are not available', () {
      final p = InboxFilterController(
        inbox: rig.inbox,
        initial: InboxFilter.none,
        baseWhere: 'me',
        isTeamShown: false,
        forms: const {},
        onApply: (_) {},
        onClear: () {},
      );
      expect(p.kindsState.value, InboxKindsState.failed);
    });
  });

  group('the conditions editor', () {
    test('add, pick a field: the operator is the kind\'s first, the value '
        'starts again', () async {
      await start();
      final (p, id) = await withBlock(['t']);
      p.addCondition(id);
      var cond = blockOf(p, id).conditions.single;
      expect(cond.isReady, isFalse);
      p.setConditionField(id, cond.id, 'title');
      cond = blockOf(p, id).conditions.single;
      expect((cond.field, cond.op), ('title', 'contains'));
      p.setConditionValue(id, cond.id, value: 'abc');
      p.setConditionField(id, cond.id, 'hours');
      cond = blockOf(p, id).conditions.single;
      expect((cond.op, cond.value), ('eq', ''));
      p.setConditionField(id, cond.id, 'due');
      expect(blockOf(p, id).conditions.single.op, 'eq');
      p.setConditionField(id, cond.id, 'ok');
      cond = blockOf(p, id).conditions.single;
      expect((cond.op, cond.value), ('eq', 'false'));
      expect(cond.isReady, isTrue);
      expect(p.operatorChoices(blockOf(p, id), cond).length, 1);
    });

    test('operators follow the field kind', () async {
      await start();
      final (p, id) = await withBlock(['t']);
      p.addCondition(id);
      final cid = blockOf(p, id).conditions.single.id;
      List<String> ops() => [
        for (final o in p.operatorChoices(
          blockOf(p, id),
          blockOf(p, id).conditions.single,
        ))
          o.id,
      ];
      p.setConditionField(id, cid, 'title');
      expect(ops(), [
        'contains',
        'eq',
        'ne',
        'starts',
        'ends',
        'empty',
        'notempty',
      ]);
      p.setConditionField(id, cid, 'hours');
      expect(ops(), [
        'eq',
        'ne',
        'gt',
        'gte',
        'lt',
        'lte',
        'between',
        'empty',
        'notempty',
      ]);
      p.setConditionField(id, cid, 'due');
      expect(ops(), [
        'eq',
        'lt',
        'gt',
        'lte',
        'gte',
        'between',
        'empty',
        'notempty',
      ]);
    });

    test('a second value is sent only for between', () async {
      await start();
      final (p, id) = await withBlock(['t']);
      p.addCondition(id);
      final cid = blockOf(p, id).conditions.single.id;
      p.setConditionField(id, cid, 'hours');
      p.setConditionOp(id, cid, 'between');
      p.setConditionValue(id, cid, value: '1');
      expect(blockOf(p, id).conditions.single.isReady, isFalse);
      p.setConditionValue(id, cid, value2: '5');
      expect(blockOf(p, id).conditions.single.toArgs(), {
        'field': 'hours',
        'op': 'between',
        'join': 'and',
        'value': '1',
        'value2': '5',
      });
      p.setConditionOp(id, cid, 'gt');
      final gt = blockOf(p, id).conditions.single;
      expect(gt.value2, '');
      expect(gt.toArgs().containsKey('value2'), isFalse);
      p.setConditionOp(id, cid, 'empty');
      expect(blockOf(p, id).conditions.single.toArgs(), {
        'field': 'hours',
        'op': 'empty',
        'join': 'and',
      });
    });

    test('And / Or between conditions, remove, and at most 20', () async {
      await start();
      final (p, id) = await withBlock(['t']);
      for (var i = 0; i < 25; i++) {
        p.addCondition(id);
      }
      expect(blockOf(p, id).conditions.length, InboxFilterLimits.maxConditions);
      expect(p.canAddCondition(blockOf(p, id)), isFalse);
      final second = blockOf(p, id).conditions[1];
      p.setConditionJoin(id, second.id, 'or');
      expect(blockOf(p, id).conditions[1].join, 'or');
      p.removeCondition(id, second.id);
      expect(blockOf(p, id).conditions.length, 19);
      expect(p.canAddCondition(blockOf(p, id)), isTrue);
    });

    test(
      'the groups sent carry the ready conditions of a one-form block',
      () async {
        await start();
        final (p, id) = await withBlock(['t']);
        p.addCondition(id);
        final cid = blockOf(p, id).conditions.single.id;
        p.setConditionField(id, cid, 'title');
        p.setConditionValue(id, cid, value: ' x ');
        final q = p.draft.value.toQuery().toArgs();
        expect(q['groups'], [
          {
            'form': 't',
            'conditions': [
              {'field': 'title', 'op': 'contains', 'join': 'and', 'value': 'x'},
            ],
          },
        ]);
      },
    );

    test('a second form hides the conditions and sends none; another form '
        'drops them; the same single form keeps them', () async {
      await start();
      final (p, id) = await withBlock(['t']);
      p.addCondition(id);
      final cid = blockOf(p, id).conditions.single.id;
      p.setConditionField(id, cid, 'ok');
      p.setBlockForms(id, ['t']);
      expect(blockOf(p, id).conditions.length, 1, reason: 'same form: kept');
      p.changeBlock(id, (b) => b.copyWith(forms: ['t', 'u']));
      expect(
        p.draft.value.groups.every((g) => (g['conditions'] as List).isEmpty),
        isTrue,
        reason: 'not sent with two forms',
      );
      p.setBlockForms(id, ['u']);
      expect(blockOf(p, id).conditions, isEmpty, reason: 'another form');
      expect(
        InboxFilterController.conditionsManyFormsText,
        contains('one data form'),
      );
    });
  });

  group('Timeline', () {
    test('is offered, stands alone, and another entry clears it', () async {
      await start();
      final p = open();
      expect(p.searchInChoices.last.id, 'timeline');
      p.setWheres(['me', 'completed']);
      p.setWheres(['me', 'completed', 'timeline']);
      expect(p.draft.value.wheres, ['timeline']);
      p.setWheres(['timeline', 'me']);
      expect(p.draft.value.wheres, ['me']);
      p.setWheres(['timeline']);
      p.setWheres(['timeline', 'escalations', 'requests']);
      expect(p.draft.value.wheres, ['escalations', 'requests']);
    });

    test('sends the same records.query as an unfiltered list', () async {
      await start();
      final unfiltered = rig.argsOf('records.query').last;
      c.applyFilter(const InboxFilter(wheres: ['timeline']));
      await settle();
      final sent = rig.argsOf('records.query').last;
      expect(sent.containsKey('views'), isFalse);
      expect(sent.containsKey('scope'), isFalse);
      const files = {'withDetails': true, 'fileMeta': 2};
      expect(sent, {'limit': 100, 'offset': 0, ...files});
      expect(unfiltered, {
        'scope': ['me'],
        'limit': 100,
        'offset': 0,
        ...files,
      });
      expect(c.isTimeline, isTrue);
    });
  });

  group('day headings', () {
    final now = DateTime(2026, 11, 24, 0, 5);
    int at(int y, int m, int d, [int h = 12, int mi = 0]) =>
        DateTime(y, m, d, h, mi).millisecondsSinceEpoch;

    test('Today, Yesterday, then the date; local day boundaries', () {
      expect(InboxTimeline.headingOf(at(2026, 11, 24, 0, 0), now), 'Today');
      expect(
        InboxTimeline.headingOf(at(2026, 11, 23, 23, 59), now),
        'Yesterday',
      );
      expect(InboxTimeline.headingOf(at(2026, 11, 23, 0, 0), now), 'Yesterday');
      expect(
        InboxTimeline.headingOf(at(2026, 11, 22, 23, 59), now),
        'Nov 22, 2026',
      );
      expect(InboxTimeline.headingOf(at(2026, 1, 3), now), 'Jan 3, 2026');
      expect(InboxTimeline.headingOf(0, now), 'No date');
    });

    test('one heading per day, newest day first, rows keep their order', () {
      InboxRow r(int id, int ts) => InboxRow(
        id: id,
        formId: 't',
        form: 'Thing',
        subject: 's$id',
        holder: '',
        raiser: '',
        ts: ts,
      );
      final rows = [
        r(1, at(2026, 11, 22)),
        r(2, at(2026, 11, 24, 0, 1)),
        r(3, at(2026, 11, 23, 23, 59)),
        r(4, at(2026, 11, 24, 9)),
        r(5, 0),
        r(6, at(2026, 11, 22, 1)),
      ];
      final days = InboxTimeline.group(rows, now);
      expect(
        [for (final d in days) d.heading],
        ['Today', 'Yesterday', 'Nov 22, 2026', 'No date'],
      );
      expect(
        [
          for (final d in days) [for (final x in d.rows) x.id],
        ],
        [
          [2, 4],
          [3],
          [1, 6],
          [5],
        ],
      );
      expect(InboxTimeline.group(const [], now), isEmpty);
    });

    test('the list items are headings and cards only under Timeline', () async {
      await start();
      rig.routes['records.query'] = (_) => queryReply([
        {...record(2), 'ts': at(2026, 11, 24, 8)},
        {...record(1), 'ts': at(2026, 11, 23, 8)},
      ]);
      await c.load();
      await settle();
      expect(c.listItems.every((i) => i.heading == null), isTrue);
      c.applyFilter(const InboxFilter(wheres: ['timeline']));
      await settle();
      expect(
        [for (final i in c.listItems) i.heading ?? i.row?.id],
        ['Today', 2, 'Yesterday', 1],
      );
    });
  });

  group('page size and totals', () {
    test(
      'the first page and the next page ask 100; 200 is still the limit',
      () async {
        await start();
        expect(InboxController.pageSize, 100);
        expect(rig.argsOf('records.query').first['limit'], 100);
        expect(
          () => const InboxQuery().toArgs(limit: 201),
          throwsA(isA<InboxQueryError>()),
        );
        expect(const InboxQuery().toArgs(limit: 200)['limit'], 200);
        expect(() => const InboxQuery().toArgs(limit: 0), throwsA(anything));
      },
    );

    test('N+ comes from the capped flag, not the number', () async {
      await start();
      rig.routes['records.query'] = (_) =>
          queryReply([record(1)], total: 1, capped: true);
      await c.load();
      await settle();
      expect(c.totalLabel, '1000+ records');
      rig.routes['records.query'] = (_) => queryReply([record(1)], total: 5000);
      await c.load();
      await settle();
      expect(c.totalLabel, '5000 records', reason: 'no flag, no plus');
      rig.routes['records.query'] = (_) => queryReply([record(1)], total: 1);
      await c.load();
      await settle();
      expect(c.totalLabel, '1 record');
    });
  });

  group('rows the server sends without some parts', () {
    final forms = InboxForm.parseAll(structures);

    test('no team: no crash, no members, state falls back as the web does', () {
      final raw = record(7, holder: 'ben', values: {'title': 'X'});
      expect(raw.containsKey('team'), isFalse);
      final row = InboxRow.tryParse(raw, forms)!;
      expect(row.via, isEmpty);
      expect(row.members, isEmpty);
      expect(row.links, isNull);
      expect(row.stateFor('ana').name, 'assigned');
      expect(row.stateFor('ben').name, 'pending');
      final odd = InboxRow.tryParse({
        ...raw,
        'team': 'nonsense',
        'labels': 5,
        'actedBy': 3,
      }, forms)!;
      expect(odd.via, isEmpty);
      expect(odd.labels, isEmpty);
    });

    test('no actedBy, no labels, no files: empty, not null', () {
      final row = InboxRow.tryParse({
        'id': 3,
        'tstruct': 't',
        'by': 'rhea',
        'ts': 5,
      }, forms)!;
      expect(row.actedBy, '');
      expect(row.labels, isEmpty);
      expect(row.externalId, '');
      expect(row.who, 'rhea');
      expect(row.priority, isNull);
    });

    test('the page parser keeps rows with neither', () {
      final page = InboxPage.parse({
        'submissions': [
          record(1),
          {'id': 2, 'tstruct': 't', 'by': 'rhea'},
        ],
        'structures': structures,
      });
      expect([for (final r in page.rows) r.id], [1, 2]);
    });
  });
}
