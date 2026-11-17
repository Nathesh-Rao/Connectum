import 'package:connectum/data/smart_view/models/sv_row.dart';
import 'package:connectum/data/smart_view/models/sv_source.dart';
import 'package:connectum/data/smart_view/sv_card_content.dart';
import 'package:connectum/data/smart_view/sv_cell_format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sv_support.dart';

void main() {
  group('source list (real capture 004)', () {
    test('parses structures; a hidden field is not in the list', () {
      final all = realSources();
      expect(all.map((s) => s.name), ['everyfield', 'requests', 'tickets']);
      final tickets = sourceNamed('tickets');
      expect(tickets.fields.map((f) => f.name), [
        'title',
        'stage',
        'area',
        'due',
        'hours',
      ]);
      expect(tickets.fieldOf('secret'), isNull);
      expect(tickets.table?.field, 'stage');
      expect(tickets.hasStatus, isTrue);
    });

    test('picker order: own before built-in, then caption A to Z', () {
      const sys = SvSource(name: 'a', caption: 'Alpha', isSystem: true);
      const own1 = SvSource(name: 'z', caption: 'Zeta');
      const own2 = SvSource(name: 'b', caption: 'Beta');
      const hidden = SvSource(name: 'h', caption: 'Hidden', canFetch: false);
      expect(SvSources.sorted([sys, own1, hidden, own2]).map((s) => s.name), [
        'b',
        'z',
        'a',
      ]);
    });

    test('find: exact name or caption first, else the first that contains', () {
      final all = [
        const SvSource(name: 'leave_request', caption: 'Leave request'),
        const SvSource(name: 'leave', caption: 'Time off'),
        const SvSource(name: 'secret', caption: 'Secret', canFetch: false),
      ];
      expect(SvSources.find(all, 'LEAVE')?.name, 'leave');
      expect(SvSources.find(all, 'leave request')?.name, 'leave_request');
      expect(SvSources.find(all, 'off')?.name, 'leave');
      expect(SvSources.find(all, 'secret'), isNull);
      expect(SvSources.find(all, 'nothing'), isNull);
      expect(SvSources.find(all, '  '), isNull);
    });

    test('suggestions: contains, starts-with first, own first, max 30', () {
      final all = [
        const SvSource(name: 'x1', caption: 'My leave', isSystem: true),
        const SvSource(name: 'x2', caption: 'Leave own'),
        const SvSource(name: 'x3', caption: 'Annual leave'),
        const SvSource(name: 'x4', caption: 'Other'),
      ];
      expect(SvSources.suggest(all, 'leave').map((s) => s.name), [
        'x2',
        'x3',
        'x1',
      ]);
      expect(SvSources.suggest(all, '').length, 4);
      final many = [
        for (var i = 0; i < 40; i++) SvSource(name: 'n$i', caption: 'C$i'),
      ];
      expect(SvSources.suggest(many, '').length, 30);
    });

    test('one item that equals the typed name: none, so Enter runs it', () {
      final all = [
        const SvSource(name: 'leave', caption: 'Leave'),
        const SvSource(name: 'other', caption: 'Other'),
      ];
      expect(SvSources.suggest(all, 'leave'), isEmpty);
      expect(SvSources.suggest(all, 'leav').length, 1);
    });
  });

  group('rows (real captures 007, 019)', () {
    test(
      'a submissions.list row keeps canEdit; a received row never has it',
      () {
        final own = SvPage.parse(captured('007'), isReceived: false);
        expect(own.rows.map((r) => r.id), [39, 37, 35]);
        expect(own.rows.first.canEdit, isTrue);
        expect(own.rows.first.byName, 'Ann Rao');
        expect(own.hasMore, isTrue);
        final got = SvPage.parse(captured('019'), isReceived: true);
        expect(got.rows.map((r) => r.id), [47, 45]);
        expect(got.rows.every((r) => !r.canEdit && r.isReceived), isTrue);
        expect(got.received, 2);
        expect(got.next, isNull);
        expect(got.hasMore, isTrue);
      },
    );

    test('a row without an id is skipped but counted as received', () {
      final page = SvPage.parse({
        'submissions': [
          {'tstruct': 'x'},
          ownRow(1),
        ],
        'hasMore': true,
      }, isReceived: false);
      expect(page.rows.length, 1);
      expect(page.received, 2);
    });

    test('approval words and With', () {
      SvRow row(String status, {String holder = '', List<String>? c}) => SvRow(
        id: 1,
        tstruct: 't',
        by: 'ann',
        ts: 1,
        recordStatus: status,
        holder: holder,
        claimants: c ?? const [],
      );
      expect(row('').approval, 'Recorded');
      expect(row('pending').approval, 'Waiting for approval');
      expect(row('rejected').approval, 'Declined');
      expect(row('approved').approval, 'Approved');
      expect(row('').withWhom, 'ann');
      expect(row('', holder: 'bob').withWhom, 'bob');
      expect(row('', holder: 'bob', c: ['cy', 'di']).withWhom, 'cy, di');
    });
  });

  group('cell text (BE document 3.8.1, vectors)', () {
    SvField f(String type, {bool rich = false}) =>
        SvField(name: 'x', caption: 'X', type: type, isRich: rich);
    String t(
      String type,
      Object? v, {
      Map<String, dynamic> labels = const {},
      Map<String, dynamic> files = const {},
      bool rich = false,
    }) => SvCell.of(
      f(type, rich: rich),
      v,
      labels: labels,
      files: files,
    );

    test('the record "Everything" of capture 010 gives the BE vector text', () {
      final everyfield = sourceNamed('everyfield');
      final row = SvPage.parse(
        captured('010'),
        isReceived: false,
      ).rows.firstWhere((r) => r.values['title'] == 'Everything');
      String cell(String name) => SvCell.of(
        everyfield.fieldOf(name),
        row.values[name],
        labels: row.labels,
        files: row.files,
      );
      expect(cell('ref'), 'VIS-0001');
      expect(cell('title'), 'Everything');
      expect(cell('notes'), 'line one\nline two');
      expect(cell('story'), 'Hello world & friends');
      expect(cell('qty'), '7');
      expect(cell('amount'), '1,234.5');
      expect(cell('day'), '12 Nov 2026');
      expect(cell('at'), '09:45');
      expect(cell('mail'), 'a@b.co');
      expect(cell('site'), 'https://example.com/x');
      expect(cell('phone'), '+919886012345');
      expect(cell('where'), 'MG Road');
      expect(cell('kind'), 'Contract');
      expect(cell('tags'), 'red, blue');
      expect(cell('owner'), 'Bob Iyer');
      expect(cell('urgent'), 'Yes');
      expect(cell('code'), '8901234567890');
      expect(cell('copy'), '–');
      expect(cell('fee'), 'INR 500 · UPI · Paid');
      expect(cell('doc'), 'Everything.pdf');
    });

    test('blank, null and empty are the dash, never null or an object', () {
      for (final type in const [
        'text',
        'number',
        'date',
        'toggle',
        'selection',
        'location',
        'payment',
        'file',
        'list',
      ]) {
        expect(t(type, null), '–', reason: type);
        expect(t(type, ''), '–', reason: type);
        expect(t(type, '   '), '–', reason: type);
      }
      expect(t('list', <String>[]), '–');
      expect(t('location', {}), '–');
      expect(t('payment', {}), '–');
      expect(t('text', {'a': 1, 'b': 2}), 'a: 1 · b: 2');
      expect(
        t('text', {
          'a': 1,
          'b': {'c': 1},
        }),
        'a: 1 · b: 1 fields',
      );
      expect(t('text', ['x', 'y']), 'x, y');
      expect(t('text', {'a': null}), '–');
    });

    test('numbers: grouped, two decimals at most, symbols and codes stay', () {
      expect(t('number', 1234.5), '1,234.5');
      expect(t('number', 1234.567), '1,234.57');
      expect(t('number', 1000000), '1,000,000');
      expect(t('number', 0), '0');
      expect(t('number', -2500.5), '-2,500.5');
      expect(t('number', '45%'), '45%');
      expect(t('number', r'$1,200'), r'$1,200');
      expect(t('number', 'abc'), 'abc');
      expect(t('number', '1234.5'), '1,234.5');
      expect(t('number', '007'), '007');
      expect(t('number', '8901234567890'), '8901234567890');
    });

    test('dates: a date is local midnight, a time adds hours and minutes', () {
      expect(t('date', '2026-11-12'), '12 Nov 2026');
      expect(t('date', '2026-11-12T09:30'), '12 Nov 2026, 09:30');
      expect(t('date', '2026-11-12 09:30'), '12 Nov 2026, 09:30');
      expect(t('slot', '2026-11-20 10:30'), '20 Nov 2026, 10:30');
      expect(t('date', 'not a date'), 'not a date');
      expect(t('time', '09:45'), '09:45');
    });

    test('toggle, choices, people, payment, files', () {
      expect(t('toggle', 'Yes'), 'Yes');
      expect(t('toggle', true), 'Yes');
      expect(t('toggle', '0'), 'No');
      expect(t('toggle', 'No'), 'No');
      expect(t('selection', 'c', labels: {'x': 'Contract'}), 'Contract');
      expect(t('selection', 'c'), 'c');
      expect(t('people', 'u1', labels: {'x': 'Bob Iyer'}), 'Bob Iyer');
      expect(t('people', 'u1'), 'u1');
      expect(t('location', {'lat': 12.9, 'lng': 77.5}), '12.9, 77.5');
      expect(
        t('payment', {'amount': 500, 'currency': 'INR', 'status': 'pending'}),
        'INR 500 · Pay later',
      );
      expect(t('payment', {'amount': 12.5, 'method': 'Cash'}), '12.5 · Cash');
      expect(t('file', ['4961748d27125c549678e385']), 'File');
      expect(t('file', ['not-an-id']), '–');
      expect(
        t(
          'file',
          ['4961748d27125c549678e385', 'ffffffffffffffffffffffff'],
          files: {
            'x': [
              {'id': '4961748d27125c549678e385', 'name': 'a.pdf'},
            ],
          },
        ),
        'a.pdf, File',
      );
    });

    test('rich text is words only, never markup', () {
      expect(
        t(
          'text',
          '<p>Hello <b>world</b> &amp; <i>friends</i><script>alert(1)</script></p>',
          rich: true,
        ),
        'Hello world & friends',
      );
      expect(t('text', 'a<br>b</p>c', rich: true), 'a b c');
      expect(
        t('text', '<style>x{}</style>ok &#65;&#x42;&nbsp;&zz;', rich: true),
        'ok AB &zz;',
      );
      expect(t('text', '<script>alert(1)', rich: true), '–');
      expect(t('text', '<b>x</b>'), '<b>x</b>');
    });
  });

  group('card content', () {
    final tickets = sourceNamed('tickets');
    final row = SvPage.parse(captured('007'), isReceived: false).rows.first;

    test(
      'the title is the first filled value, hidden fields are never read',
      () {
        final c = SvCardContent.of(tickets, row);
        expect(c.title, 'Printer jammed');
        expect(c.number, '39');
        expect(c.by, 'Ann Rao');
        expect(c.approval, '');
        expect(c.pairs.map((p) => p.label), ['Area', 'Due', 'Hours']);
        expect(c.pairs.map((p) => p.value), ['Delivery', '20 Nov 2026', '2.5']);
        final all = [
          c.title,
          c.by,
          c.submitted,
          ...c.pairs.map((p) => p.value),
        ];
        expect(all.any((s) => s.contains('HIDDEN')), isFalse);
        expect(c.pairs.any((p) => p.label == 'Internal note'), isFalse);
      },
    );

    test(
      'a key field leads; a record with nothing filled is "<caption> #id"',
      () {
        const withKey = SvSource(
          name: 's',
          caption: 'Cap',
          keyField: 'code',
          fields: [
            SvField(name: 'code', caption: 'Code'),
            SvField(name: 'other', caption: 'Other'),
          ],
        );
        final a = SvRow(
          id: 3,
          tstruct: 's',
          by: 'ann',
          ts: 1,
          values: {'code': 'K-1', 'other': 'o'},
        );
        final c = SvCardContent.of(withKey, a);
        expect(c.title, 'K-1');
        expect(c.pairs.map((p) => p.label), ['Other']);
        final blank = SvRow(id: 4, tstruct: 's', by: 'ann', ts: 0);
        expect(SvCardContent.of(withKey, blank).title, 'Cap #4');
        expect(SvCardContent.of(withKey, blank).submitted, '–');
      },
    );

    test('a waiting record shows its approval word, a recorded one none', () {
      final waiting = row.copyWith(recordStatus: 'pending');
      expect(
        SvCardContent.of(tickets, waiting).approval,
        'Waiting for approval',
      );
    });
  });
}
