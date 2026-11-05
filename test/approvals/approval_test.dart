import 'package:connectum/data/models/approval.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final submission = {
    'approvers': ['meg'],
    'canRespond': true,
    'createdTs': 1793477900047,
    'data': {
      'caption': 'Expense claim',
      'message': 'Emma Employee submitted Expense claim',
      'stage': 1,
      'stages': 2,
      'submissionId': 30,
      'summary': [
        {'caption': 'Amount', 'value': '120'},
      ],
      'tstruct': 'expense',
    },
    'direction': 'incoming',
    'from': 'emma',
    'fromName': 'Emma Employee',
    'id': 1,
    'resolvedBy': null,
    'resolvedTs': null,
    'status': 'pending',
    'subject': 'emma',
    'subjectName': 'Emma Employee',
    'type': 'submission',
  };

  test('a submission request parses with its summary', () {
    final r = Approval.tryParse(submission)!;
    expect(r.id, 1);
    expect(r.type, 'submission');
    expect(r.isSubmission, isTrue);
    expect(r.isIncoming, isTrue);
    expect(r.canRespond, isTrue);
    expect(r.caption, 'Expense claim');
    expect(r.stage, 1);
    expect(r.stages, 2);
    expect(r.lines.single.caption, 'Amount');
    expect(r.lines.single.value, '120');
    expect(r.approvers, ['meg']);
    expect(r.resolvedTs, isNull);
  });

  test('missing fields fall back and do not throw', () {
    final r = Approval.tryParse({'id': 4})!;
    expect(r.status, Approval.pending);
    expect(r.direction, Approval.other);
    expect(r.canRespond, isFalse);
    expect(r.lines, isEmpty);
    expect(r.approvers, isEmpty);
    expect(r.fromLabel, '');
  });

  test('data that is not a map and a summary that is not a list', () {
    final r = Approval.tryParse({'id': 4, 'data': 'x'})!;
    expect(r.caption, '');
    final s = Approval.tryParse({
      'id': 5,
      'data': {'summary': 'x'},
    })!;
    expect(s.lines, isEmpty);
  });

  test('no id means no request', () {
    expect(Approval.tryParse({'type': 'x'}), isNull);
    expect(Approval.tryParse(null), isNull);
  });

  test('an event has no direction: it is worked out for the viewer', () {
    final event = {...submission}
      ..remove('direction')
      ..remove('canRespond');
    final incoming = Approval.tryParse(event, viewer: 'MEG')!;
    expect(incoming.direction, Approval.incoming);
    expect(incoming.canRespond, isTrue);
    final outgoing = Approval.tryParse(event, viewer: 'emma')!;
    expect(outgoing.direction, Approval.outgoing);
    expect(outgoing.canRespond, isFalse);
    final other = Approval.tryParse(event, viewer: 'zed')!;
    expect(other.direction, Approval.other);
  });

  test('a resolved event cannot be answered', () {
    final event = {...submission, 'status': 'accepted'}
      ..remove('direction')
      ..remove('canRespond');
    expect(Approval.tryParse(event, viewer: 'meg')!.canRespond, isFalse);
  });

  test('a page parses', () {
    final page = ApprovalPage.parse({
      'requests': [
        submission,
        {'nope': 1},
      ],
      'total': 9,
      'hasMore': true,
    });
    expect(page.requests, hasLength(1));
    expect(page.total, 9);
    expect(page.hasMore, isTrue);
  });
}
