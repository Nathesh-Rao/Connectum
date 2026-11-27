import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/inbox/models/approval_pane.dart';
import 'package:flutter_test/flutter_test.dart';

Approval ap(
  int id, {
  String type = 'submission',
  String status = Approval.pending,
  bool canRespond = true,
  String direction = Approval.incoming,
  int createdTs = 1000,
  List<ApprovalLine> lines = const [],
  int? stage,
  int? stages,
  String caption = '',
  bool returned = false,
}) => Approval(
  id: id,
  type: type,
  status: status,
  canRespond: canRespond,
  direction: direction,
  createdTs: createdTs,
  lines: lines,
  stage: stage,
  stages: stages,
  caption: caption,
  returned: returned,
);

void main() {
  group('count', () {
    test('only pending and canRespond; requests the person sent never', () {
      final all = [
        ap(1),
        ap(2),
        ap(3, canRespond: false, direction: Approval.outgoing),
        ap(4, status: Approval.accepted, canRespond: false),
        ap(5, status: Approval.rejected, canRespond: false),
        ap(6, canRespond: false),
      ];
      expect(ApprovalPane.countOf(all), 2);
    });

    test('a settled sign-up is not counted, a waiting one is', () {
      expect(
        ApprovalPane.countOf([
          ap(1, type: 'onboarding'),
          ap(
            2,
            type: 'onboarding',
            status: Approval.accepted,
            canRespond: false,
          ),
        ]),
        1,
      );
    });
  });

  group('state and tag', () {
    test('state follows the status', () {
      expect(ApprovalPane.stateOf(ap(1)), ApprovalState.pending);
      expect(
        ApprovalPane.stateOf(ap(1, status: 'rejected')),
        ApprovalState.rejected,
      );
      expect(
        ApprovalPane.stateOf(ap(1, status: 'accepted')),
        ApprovalState.approved,
      );
      expect(
        ApprovalPane.stateOf(ap(1, status: 'approved')),
        ApprovalState.approved,
      );
      expect(
        ApprovalPane.stateOf(ap(1, status: 'ignored')),
        ApprovalState.other,
      );
    });

    test('tags', () {
      expect(ApprovalPane.tagOf(ap(1)), 'Waiting for you');
      expect(
        ApprovalPane.tagOf(ap(1, canRespond: false)),
        'Waiting for approval',
      );
      expect(ApprovalPane.tagOf(ap(1, status: 'rejected')), 'Declined');
      expect(
        ApprovalPane.tagOf(ap(1, status: 'rejected', returned: true)),
        'Returned',
      );
      expect(
        ApprovalPane.statusWord(ap(1, status: 'rejected', returned: true)),
        'Returned',
      );
      expect(ApprovalPane.tagOf(ap(1, status: 'accepted')), 'Approved');
      expect(ApprovalPane.tagOf(ap(1, status: 'ignored')), '');
    });
  });

  group('rows', () {
    test('every state is listed, newest first by createdTs', () {
      final all = [
        ap(1, createdTs: 10),
        ap(2, status: 'accepted', canRespond: false, createdTs: 30),
        ap(3, status: 'rejected', canRespond: false, createdTs: 20),
        ap(4, status: 'ignored', canRespond: false, createdTs: 5),
      ];
      // A dismissed (ignored) request is not listed anywhere.
      expect([for (final a in ApprovalPane.listed(all)) a.id], [2, 3, 1]);
    });

    test('only a waiting sign-up is listed (the web rule, HashInboxModal)', () {
      final all = [
        ap(1, type: 'onboarding'),
        ap(2, type: 'onboarding', status: 'accepted', canRespond: false),
        ap(3, type: 'onboarding', status: 'rejected', canRespond: false),
        ap(4, type: 'onboarding', status: 'withdrawn', canRespond: false),
      ];
      expect([for (final a in ApprovalPane.listed(all)) a.id], [1]);
    });

    test('the search text narrows the rows', () {
      final all = [
        ap(1, caption: 'Expense claim'),
        ap(2, caption: 'Leave request'),
        ap(3, status: 'accepted', canRespond: false, caption: 'Expense claim'),
      ];
      List<int> ids(String q) => [
        for (final a in ApprovalPane.rows(all, query: q)) a.id,
      ];
      expect(ids('expense'), [3, 1]);
      expect(ids('nothing like it'), isEmpty);
    });
  });

  group('escalation', () {
    final now = DateTime.fromMillisecondsSinceEpoch(10 * 86400 * 1000);
    int ago(Duration d) => now.millisecondsSinceEpoch - d.inMilliseconds;

    test('exactly 3 days is not escalated, one millisecond more is', () {
      expect(
        ApprovalPane.isEscalated(
          ap(1, createdTs: ago(const Duration(days: 3))),
          now,
        ),
        isFalse,
      );
      expect(
        ApprovalPane.isEscalated(
          ap(1, createdTs: ago(const Duration(days: 3, milliseconds: 1))),
          now,
        ),
        isTrue,
      );
    });

    test('only what waits for the person; a recent one is not', () {
      final old = ago(const Duration(days: 9));
      expect(
        ApprovalPane.isEscalated(ap(1, createdTs: old, canRespond: false), now),
        isFalse,
      );
      expect(
        ApprovalPane.isEscalated(
          ap(1, createdTs: old, status: 'accepted', canRespond: false),
          now,
        ),
        isFalse,
      );
      expect(
        ApprovalPane.isEscalated(
          ap(1, createdTs: ago(const Duration(hours: 5))),
          now,
        ),
        isFalse,
      );
    });
  });

  group('kinds and card rows', () {
    test('labels', () {
      String k(String t) => ApprovalPane.kindLabel(ap(1, type: t));
      expect(k('onboarding'), 'Sign-up');
      expect(k('membership'), 'Connection request');
      expect(k('associate'), 'Connection request');
      expect(k('handover'), 'Introduction');
      expect(k('group_invite'), 'Group invitation');
      expect(k('host_transfer'), 'Transfer');
      expect(k('submission'), 'Form');
      expect(k('whatever'), 'Request');
    });

    test('a form card lists its summary answers and the step', () {
      final a = ap(
        1,
        caption: 'Expense claim',
        lines: const [ApprovalLine('Amount', '120')],
        stage: 1,
        stages: 2,
      );
      expect(ApprovalPane.titleOf(a), 'Expense claim');
      final rows = ApprovalPane.detailRows(a);
      expect(rows, contains(('Amount', '120')));
      expect(rows, contains(('Progress', 'Step 1 of 2')));
    });
  });
}
