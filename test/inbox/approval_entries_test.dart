import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/inbox/models/approval_chips.dart';
import 'package:connectum/features/inbox/models/approval_entries.dart';
import 'package:connectum/features/inbox/models/approval_pane.dart';
import 'package:flutter_test/flutter_test.dart';

const _who = ApprovalWho(me: 'ana', team: {'rhea', 'sam'});

Approval ap(
  int id, {
  String status = 'pending',
  String direction = 'other',
  bool canRespond = false,
  String fromUser = 'zed',
  String? resolvedBy,
  bool returned = false,
  List<String> approvers = const [],
}) => Approval(
  id: id,
  type: 'submission',
  status: status,
  direction: direction,
  canRespond: canRespond,
  from: fromUser,
  fromUser: fromUser,
  resolvedBy: resolvedBy,
  returned: returned,
  approvers: approvers,
);

bool inEntry(Approval a, ApprovalEntry e) =>
    ApprovalEntries.inEntry(a, e, _who);

Set<ApprovalEntry> entriesOf(Approval a) => {
  for (final e in ApprovalEntry.values)
    if (inEntry(a, e)) e,
};

void main() {
  group('each entry, with the backend table', () {
    test('Sent to me: an approver, or somebody who may answer it', () {
      expect(
        inEntry(ap(1, direction: 'incoming'), ApprovalEntry.sentToMe),
        isTrue,
      );
      expect(
        inEntry(
          ap(1, direction: 'other', canRespond: true),
          ApprovalEntry.sentToMe,
        ),
        isTrue,
      );
      expect(
        inEntry(ap(1, direction: 'outgoing'), ApprovalEntry.sentToMe),
        isFalse,
      );
      expect(
        inEntry(
          ap(1, status: 'accepted', direction: 'other', canRespond: true),
          ApprovalEntry.sentToMe,
        ),
        isFalse,
      );
    });

    test('Sent by me: the person raised it (outgoing), any answer', () {
      for (final s in ['pending', 'accepted', 'rejected']) {
        expect(
          inEntry(
            ap(1, status: s, direction: 'outgoing'),
            ApprovalEntry.sentByMe,
          ),
          isTrue,
          reason: s,
        );
      }
      expect(
        inEntry(ap(1, direction: 'incoming'), ApprovalEntry.sentByMe),
        isFalse,
      );
    });

    test('Sent by team: a direct report raised it, any answer', () {
      for (final s in ['pending', 'accepted', 'rejected']) {
        expect(
          inEntry(ap(1, status: s, fromUser: 'rhea'), ApprovalEntry.sentByTeam),
          isTrue,
          reason: s,
        );
      }
      expect(
        inEntry(ap(1, fromUser: 'zed'), ApprovalEntry.sentByTeam),
        isFalse,
      );
    });

    test('Pending by me: I raised it and it still waits', () {
      expect(
        inEntry(ap(1, direction: 'outgoing'), ApprovalEntry.pendingByMe),
        isTrue,
      );
      expect(
        inEntry(
          ap(1, status: 'accepted', direction: 'outgoing'),
          ApprovalEntry.pendingByMe,
        ),
        isFalse,
      );
    });

    test('Pending with me: it waits for my answer (canRespond true)', () {
      expect(
        inEntry(
          ap(1, direction: 'incoming', canRespond: true),
          ApprovalEntry.pendingWithMe,
        ),
        isTrue,
      );
      expect(
        inEntry(ap(1, direction: 'incoming'), ApprovalEntry.pendingWithMe),
        isFalse,
      );
    });

    test('Pending to team: a report raised it and it waits for my answer', () {
      expect(
        inEntry(
          ap(1, fromUser: 'rhea', canRespond: true),
          ApprovalEntry.pendingToTeam,
        ),
        isTrue,
      );
      expect(
        inEntry(ap(1, fromUser: 'rhea'), ApprovalEntry.pendingToTeam),
        isFalse,
      );
      expect(
        inEntry(
          ap(1, fromUser: 'zed', canRespond: true),
          ApprovalEntry.pendingToTeam,
        ),
        isFalse,
      );
    });

    test(
      'Approved by me / Rejected by me: I answered it (resolvedBy is me)',
      () {
        expect(
          inEntry(
            ap(1, status: 'accepted', resolvedBy: 'Ana'),
            ApprovalEntry.approvedByMe,
          ),
          isTrue,
        );
        expect(
          inEntry(
            ap(1, status: 'accepted', resolvedBy: 'bob'),
            ApprovalEntry.approvedByMe,
          ),
          isFalse,
        );
        expect(
          inEntry(ap(1, status: 'accepted'), ApprovalEntry.approvedByMe),
          isFalse,
        );
        expect(
          inEntry(
            ap(1, status: 'rejected', resolvedBy: 'ana'),
            ApprovalEntry.rejectedByMe,
          ),
          isTrue,
        );
      },
    );

    test(
      'Approved for me / Rejected for me: I raised it and it was answered',
      () {
        expect(
          inEntry(
            ap(1, status: 'accepted', direction: 'outgoing', resolvedBy: 'bob'),
            ApprovalEntry.approvedForMe,
          ),
          isTrue,
        );
        expect(
          inEntry(
            ap(1, status: 'rejected', direction: 'outgoing', resolvedBy: 'bob'),
            ApprovalEntry.rejectedForMe,
          ),
          isTrue,
        );
        expect(
          inEntry(
            ap(1, status: 'rejected', direction: 'incoming', resolvedBy: 'bob'),
            ApprovalEntry.rejectedForMe,
          ),
          isFalse,
        );
      },
    );

    test(
      'Approved to team / Rejected to team: a report raised it, I answered',
      () {
        expect(
          inEntry(
            ap(1, status: 'accepted', fromUser: 'sam', resolvedBy: 'ana'),
            ApprovalEntry.approvedToTeam,
          ),
          isTrue,
        );
        expect(
          inEntry(
            ap(1, status: 'rejected', fromUser: 'sam', resolvedBy: 'ana'),
            ApprovalEntry.rejectedToTeam,
          ),
          isTrue,
        );
        expect(
          inEntry(
            ap(1, status: 'accepted', fromUser: 'sam', resolvedBy: 'bob'),
            ApprovalEntry.approvedToTeam,
          ),
          isFalse,
        );
        expect(
          inEntry(
            ap(1, status: 'accepted', fromUser: 'zed', resolvedBy: 'ana'),
            ApprovalEntry.approvedToTeam,
          ),
          isFalse,
        );
      },
    );

    test('there is no "Sent to team" and no "Approved by team"', () {
      final labels = [for (final e in ApprovalEntry.values) e.label];
      expect(labels, isNot(contains('Sent to team')));
      expect(labels, isNot(contains('Approved by team')));
      expect(labels, hasLength(12));
    });
  });

  group('the chips hold the right entries on each side', () {
    List<String> names(ApprovalPrimary c, ApprovalSide s) => [
      for (final e in ApprovalEntries.entriesOf(c, s)) e.name,
    ];

    test('Me side', () {
      expect(names(ApprovalPrimary.pending, ApprovalSide.me), [
        'pendingByMe',
        'pendingWithMe',
      ]);
      expect(names(ApprovalPrimary.approved, ApprovalSide.me), [
        'approvedByMe',
        'approvedForMe',
      ]);
      expect(names(ApprovalPrimary.requests, ApprovalSide.me), [
        'sentToMe',
        'sentByMe',
      ]);
      expect(names(ApprovalPrimary.rejected, ApprovalSide.me), [
        'rejectedByMe',
        'rejectedForMe',
      ]);
      expect(names(ApprovalPrimary.all, ApprovalSide.me), hasLength(8));
    });

    test('My Team side', () {
      expect(names(ApprovalPrimary.pending, ApprovalSide.team), [
        'pendingToTeam',
      ]);
      expect(names(ApprovalPrimary.approved, ApprovalSide.team), [
        'approvedToTeam',
      ]);
      expect(names(ApprovalPrimary.requests, ApprovalSide.team), [
        'sentByTeam',
      ]);
      expect(names(ApprovalPrimary.rejected, ApprovalSide.team), [
        'rejectedToTeam',
      ]);
      expect(names(ApprovalPrimary.all, ApprovalSide.team), hasLength(4));
    });

    final rows = [
      ap(1, direction: 'incoming', canRespond: true), // pending with me
      ap(2, direction: 'outgoing'), // pending by me
      ap(3, status: 'accepted', direction: 'outgoing', resolvedBy: 'bob'),
      ap(4, status: 'accepted', direction: 'incoming', resolvedBy: 'ana'),
      ap(5, status: 'rejected', direction: 'outgoing', resolvedBy: 'bob'),
      ap(
        6,
        status: 'rejected',
        direction: 'incoming',
        resolvedBy: 'ana',
        returned: true,
      ),
      ap(
        7,
        fromUser: 'rhea',
        canRespond: true,
      ), // pending to team (+ with me? other dir)
      ap(8, status: 'accepted', fromUser: 'sam', resolvedBy: 'ana'),
      ap(9, status: 'rejected', fromUser: 'sam', resolvedBy: 'ana'),
      ap(10, status: 'ignored', direction: 'outgoing'),
      ap(11, status: 'withdrawn', direction: 'incoming', canRespond: true),
    ];

    test('counts on the Me side', () {
      final c = ApprovalEntries.countsOf(rows, ApprovalSide.me, _who);
      // 1 and 7 wait for me; 2 is pending by me.
      expect(c[ApprovalPrimary.pending], 3);
      // 4 by me; 3 for me; 8 (a report's, I approved) is approved by me too.
      expect(c[ApprovalPrimary.approved], 3);
      // 6 and 9 by me; 5 for me.
      expect(c[ApprovalPrimary.rejected], 3);
      // sent to me: 1, 4, 6, 7 (10 and 11 are not listed); sent by me: 2, 3, 5.
      expect(c[ApprovalPrimary.requests], 7);
      expect(c[ApprovalPrimary.all], 9);
    });

    test('counts on the My Team side', () {
      final c = ApprovalEntries.countsOf(rows, ApprovalSide.team, _who);
      expect(c[ApprovalPrimary.pending], 1);
      expect(c[ApprovalPrimary.approved], 1);
      expect(c[ApprovalPrimary.rejected], 1);
      expect(c[ApprovalPrimary.requests], 3);
      expect(c[ApprovalPrimary.all], 3);
    });
  });

  group('returned, dismissed and withdrawn', () {
    test('a returned request counts as a rejection and says Returned', () {
      final a = ap(1, status: 'rejected', returned: true, resolvedBy: 'ana');
      expect(ApprovalEntries.stateOf(a), ApprovalState.rejected);
      expect(entriesOf(a), contains(ApprovalEntry.rejectedByMe));
      expect(
        ApprovalEntries.inChip(
          a,
          ApprovalPrimary.rejected,
          ApprovalSide.me,
          _who,
        ),
        isTrue,
      );
      expect(ApprovalPane.tagOf(a), 'Returned');
      expect(ApprovalPane.statusWord(a), 'Returned');
      expect(
        ApprovalPane.tagOf(ap(1, status: 'rejected', resolvedBy: 'ana')),
        'Declined',
      );
    });

    test('a dismissed or withdrawn request is in no entry and not listed', () {
      for (final s in ['ignored', 'dismissed', 'withdrawn', 'cancelled', '']) {
        final a = ap(
          1,
          status: s.isEmpty ? 'weird' : s,
          direction: 'outgoing',
          canRespond: true,
          fromUser: 'rhea',
          resolvedBy: 'ana',
        );
        expect(entriesOf(a), isEmpty, reason: s);
        expect(ApprovalPane.isListed(a), isFalse, reason: s);
        expect(ApprovalPane.listed([a]), isEmpty, reason: s);
        for (final c in ApprovalPrimary.values) {
          for (final side in ApprovalSide.values) {
            expect(ApprovalEntries.inChip(a, c, side, _who), isFalse);
          }
        }
      }
    });

    test('there is no Closed bucket: the secondary groups hold no status', () {
      expect(
        [for (final g in ApprovalChipGroup.values) g.name],
        ['direction', 'focus', 'kind', 'form', 'stage'],
      );
      expect(
        [for (final c in ApprovalPrimary.values) c.label],
        ['All', 'Pending', 'Approved', 'Requests', 'Rejected'],
      );
    });
  });

  group('the secondary chips agree with the entries', () {
    final ctx = ApprovalChipContext(me: 'ana', now: DateTime(2026, 11, 25));

    test('From me is Sent by me; To me is Sent to me', () {
      final all = [
        ap(1, direction: 'outgoing'),
        ap(2, direction: 'incoming'),
        ap(3, direction: 'other', canRespond: true),
        ap(4, status: 'accepted', direction: 'other', canRespond: true),
        ap(5, direction: 'other'),
      ];
      for (final a in all) {
        expect(
          ApprovalChips.isFromMe(a, ctx),
          inEntry(a, ApprovalEntry.sentByMe),
          reason: '${a.id}',
        );
        expect(
          ApprovalChips.isToMe(a),
          inEntry(a, ApprovalEntry.sentToMe),
          reason: '${a.id}',
        );
      }
    });

    test('Waiting for you is Pending with me', () {
      for (final a in [
        ap(1, direction: 'incoming', canRespond: true),
        ap(2, direction: 'incoming'),
        ap(3, status: 'accepted', canRespond: true),
      ]) {
        expect(
          ApprovalPane.isWaitingForMe(a),
          inEntry(a, ApprovalEntry.pendingWithMe),
        );
      }
    });
  });
}
