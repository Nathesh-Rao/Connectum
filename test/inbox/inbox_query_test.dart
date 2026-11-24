import 'package:connectum/data/records/record_commands.dart';
import 'package:connectum/features/inbox/models/inbox_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the command names live in one place', () {
    expect(RecordCmd.query, 'records.query');
    expect(RecordCmd.counts, 'records.counts');
    expect(RecordCmd.queryPeople, 'records.people');
    expect(RecordCmd.peopleCards, 'people.cards');
  });

  test('an empty ask sends only the page', () {
    expect(const InboxQuery().toArgs(), {'limit': 50, 'offset': 0});
  });

  test('every shared field is sent, only when set', () {
    final args = const InboxQuery(
      scope: ['me'],
      forms: ['tickets'],
      createdBy: ['me', 'ravi'],
      sentBy: ['sana'],
      sentTo: ['maya'],
      taggedTo: ['arun'],
      from: '2026-11-01',
      to: '2026-11-24',
      status: 'open',
      views: [
        {
          'scope': ['team'],
        },
      ],
    ).toArgs(limit: 100, offset: 200);
    expect(args, {
      'scope': ['me'],
      'forms': ['tickets'],
      'createdBy': ['me', 'ravi'],
      'sentBy': ['sana'],
      'sentTo': ['maya'],
      'taggedTo': ['arun'],
      'from': '2026-11-01',
      'to': '2026-11-24',
      'status': 'open',
      'views': [
        {
          'scope': ['team'],
        },
      ],
      'limit': 100,
      'offset': 200,
    });
  });

  test('one empty view is every record: no views field', () {
    expect(
      const InboxQuery(views: [{}]).toArgs().containsKey('views'),
      isFalse,
    );
    expect(
      const InboxQuery(views: [{}, {}]).toArgs().containsKey('views'),
      isTrue,
    );
  });

  test('limit is 1-200 and offset 0-1,000,000', () {
    const q = InboxQuery();
    expect(q.toArgs(limit: 1)['limit'], 1);
    expect(q.toArgs(limit: 200)['limit'], 200);
    expect(() => q.toArgs(limit: 0), throwsA(isA<InboxQueryError>()));
    expect(() => q.toArgs(limit: 201), throwsA(isA<InboxQueryError>()));
    expect(() => q.toArgs(offset: -1), throwsA(isA<InboxQueryError>()));
    expect(q.toArgs(offset: 1000000)['offset'], 1000000);
    expect(() => q.toArgs(offset: 1000001), throwsA(isA<InboxQueryError>()));
  });

  test('names: at most 50, each 1-200 characters, in every people list', () {
    List<String> names(int n) => [for (var i = 0; i < n; i++) 'u$i'];
    expect(
      InboxQuery(createdBy: names(50)).toArgs()['createdBy'],
      hasLength(50),
    );
    for (final q in [
      InboxQuery(createdBy: names(51)),
      InboxQuery(sentBy: names(51)),
      InboxQuery(sentTo: names(51)),
      InboxQuery(taggedTo: names(51)),
      InboxQuery(forms: names(51)),
      InboxQuery(createdBy: ['x' * 201]),
      const InboxQuery(sentTo: ['']),
    ]) {
      expect(() => q.toArgs(), throwsA(isA<InboxQueryError>()));
    }
    expect(
      InboxQuery(createdBy: ['x' * 200]).toArgs()['createdBy'],
      hasLength(1),
    );
  });

  test('at most 8 views', () {
    final eight = [
      for (var i = 0; i < 8; i++) <String, dynamic>{'status': 'open'},
    ];
    expect(InboxQuery(views: eight).toArgs()['views'], hasLength(8));
    expect(
      () => InboxQuery(
        views: [
          ...eight,
          {'status': 'closed'},
        ],
      ).toArgs(),
      throwsA(isA<InboxQueryError>()),
    );
  });

  test('scope, days and status are checked', () {
    expect(
      () => const InboxQuery(scope: ['all']).toArgs(),
      throwsA(isA<InboxQueryError>()),
    );
    expect(
      () => const InboxQuery(from: '24/11/2026').toArgs(),
      throwsA(isA<InboxQueryError>()),
    );
    expect(
      () => const InboxQuery(to: '2026-11-2').toArgs(),
      throwsA(isA<InboxQueryError>()),
    );
    expect(
      () => const InboxQuery(status: 'read').toArgs(),
      throwsA(isA<InboxQueryError>()),
    );
    expect(const InboxQuery(status: 'closed').toArgs()['status'], 'closed');
  });
}
