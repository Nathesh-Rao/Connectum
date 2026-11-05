import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/approvals/models/approval_reducer.dart';
import 'package:flutter_test/flutter_test.dart';

Approval r(
  int id, {
  String status = Approval.pending,
  String direction = Approval.incoming,
  bool canRespond = true,
  int createdTs = 0,
}) => Approval(
  id: id,
  status: status,
  direction: direction,
  canRespond: canRespond,
  createdTs: createdTs,
);

List<int> ids(List<Approval> l) => [for (final x in l) x.id];

void main() {
  test('request_created joins a pending list, newest first, once', () {
    final list = ApprovalReducer.applyCreated(
      [r(1, createdTs: 10)],
      r(2, createdTs: 20),
      status: 'pending',
    );
    expect(ids(list), [2, 1]);
    expect(ids(ApprovalReducer.applyCreated(list, r(2), status: 'pending')), [
      2,
      1,
    ]);
  });

  test('request_created does not join a history list', () {
    expect(
      ids(ApprovalReducer.applyCreated([r(1)], r(2), status: 'accepted')),
      [1],
    );
  });

  test('request_resolved updates the card in place and ends the buttons', () {
    final list = ApprovalReducer.applyResolved([
      r(1),
      r(2),
    ], r(1, status: Approval.accepted, canRespond: false, direction: 'other'));
    expect(ids(list), [1, 2]);
    expect(list.first.status, Approval.accepted);
    expect(list.first.canRespond, isFalse);
    expect(list.first.direction, Approval.incoming);
  });

  test('request_resolved for a request not shown changes nothing', () {
    final list = [r(1)];
    expect(
      ApprovalReducer.applyResolved(list, r(9, status: Approval.rejected)),
      hasLength(1),
    );
  });

  test('a resolved event keeps who answered', () {
    final event = Approval(
      id: 1,
      status: Approval.rejected,
      resolvedBy: 'meg',
      resolvedByName: 'Meg M',
      resolvedTs: 5,
      reason: 'Wrong amount',
    );
    final card = ApprovalReducer.applyResolved([r(1)], event).single;
    expect(card.resolvedByLabel, 'Meg M');
    expect(card.reason, 'Wrong amount');
    expect(card.resolvedTs, 5);
  });

  test('tabs: waiting on me, and sent by me', () {
    expect(ApprovalReducer.inReview(r(1)), isTrue);
    expect(
      ApprovalReducer.inReview(
        r(1, direction: Approval.other, canRespond: true),
      ),
      isTrue,
    );
    expect(
      ApprovalReducer.inReview(
        r(1, direction: Approval.outgoing, canRespond: false),
      ),
      isFalse,
    );
    expect(ApprovalReducer.inSent(r(1, direction: Approval.outgoing)), isTrue);
  });

  test('a refresh keeps cards answered here that the page no longer lists', () {
    final fresh = [r(2)];
    final old = [r(1, status: Approval.accepted, canRespond: false), r(2)];
    expect(ids(ApprovalReducer.refreshed(fresh, old, {1})), contains(1));
    expect(ids(ApprovalReducer.refreshed(fresh, old, {})), [2]);
  });

  test('remove and append', () {
    expect(ids(ApprovalReducer.remove([r(1), r(2)], 1)), [2]);
    expect(ids(ApprovalReducer.appended([r(1)], [r(1), r(2)])), [1, 2]);
  });
}
