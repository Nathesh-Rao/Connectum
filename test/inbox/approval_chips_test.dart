import 'package:connectum/data/models/approval.dart';
import 'package:connectum/features/inbox/models/approval_chips.dart';
import 'package:connectum/features/inbox/models/approval_rules.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 25, 12);
final ctx = ApprovalChipContext(me: 'ana', now: now);

Approval ap(
  int id, {
  String type = 'associate',
  String status = 'pending',
  String direction = 'incoming',
  bool canRespond = true,
  String from = 'rhea',
  String formId = '',
  String caption = '',
  int? stage,
  int? stages,
  Duration age = const Duration(hours: 1),
}) => Approval(
  id: id,
  type: type,
  status: status,
  direction: direction,
  canRespond: canRespond,
  from: from,
  formId: formId,
  caption: caption,
  stage: stage,
  stages: stages,
  createdTs: now.subtract(age).millisecondsSinceEpoch,
);

List<int> ids(Iterable<Approval> a) => [for (final x in a) x.id];

void main() {
  group('kinds', () {
    final cases = {
      'onboarding': ApprovalKind.signUp,
      'membership': ApprovalKind.connection,
      'associate': ApprovalKind.connection,
      'handover': ApprovalKind.introduction,
      'group_invite': ApprovalKind.groupInvite,
      'host_transfer': ApprovalKind.transfer,
      'submission': ApprovalKind.form,
      'wizard': ApprovalKind.other,
      'brand-new': ApprovalKind.other,
      '': ApprovalKind.other,
    };
    for (final e in cases.entries) {
      test('"${e.key}" is ${e.value.name}, in exactly one kind', () {
        final a = ap(1, type: e.key);
        expect(ApprovalChips.kindOf(a), e.value);
        expect(
          ApprovalKind.values
              .where(
                (k) =>
                    ApprovalChips.inChip(a, ApprovalChipGroup.kind, k.key, ctx),
              )
              .length,
          1,
        );
      });
    }
  });

  group('direction', () {
    test('From me is the entry Sent by me: the server says outgoing', () {
      expect(ApprovalChips.isFromMe(ap(1, direction: 'outgoing'), ctx), isTrue);
      expect(ApprovalChips.isFromMe(ap(1, from: 'Ana'), ctx), isFalse);
      expect(ApprovalChips.isFromMe(ap(1), ctx), isFalse);
    });
    test('To me is the entry Sent to me: incoming, or it waits for me', () {
      expect(ApprovalChips.isToMe(ap(1, canRespond: false)), isTrue);
      expect(
        ApprovalChips.isToMe(
          ap(1, direction: 'other', status: 'accepted', canRespond: true),
        ),
        isFalse,
      );
      expect(
        ApprovalChips.isToMe(ap(1, direction: 'other', canRespond: true)),
        isTrue,
      );
      expect(
        ApprovalChips.isToMe(ap(1, direction: 'outgoing', canRespond: false)),
        isFalse,
      );
    });
    test('the pairs cover everything and never overlap', () {
      for (final d in ['incoming', 'outgoing', 'other']) {
        for (final c in [true, false]) {
          for (final f in ['ana', 'rhea']) {
            final a = ap(1, direction: d, canRespond: c, from: f);
            bool on(String k) =>
                ApprovalChips.inChip(a, ApprovalChipGroup.direction, k, ctx);
            expect(on('from_me') != on('not_from_me'), isTrue);
            expect(on('to_me') != on('not_to_me'), isTrue);
          }
        }
      }
    });
  });

  group('focus', () {
    test(
      'Waiting for you is pending and canRespond; Escalated after 3 days',
      () {
        final fresh = ap(1);
        final old = ap(2, age: const Duration(days: 4));
        final mine = ap(3, direction: 'outgoing', canRespond: false);
        final done = ap(4, status: 'accepted', canRespond: false);
        bool w(Approval a) =>
            ApprovalChips.inChip(a, ApprovalChipGroup.focus, 'waiting', ctx);
        bool e(Approval a) =>
            ApprovalChips.inChip(a, ApprovalChipGroup.focus, 'escalated', ctx);
        expect([fresh, old, mine, done].map(w), [true, true, false, false]);
        expect([fresh, old, mine, done].map(e), [false, true, false, false]);
      },
    );
  });

  group('combining', () {
    final rows = [
      ap(1),
      ap(
        2,
        type: 'submission',
        formId: 'leave',
        caption: 'Leave',
        stage: 1,
        stages: 3,
      ),
      ap(
        3,
        type: 'submission',
        formId: 'expense',
        caption: 'Expense',
        stage: 2,
        stages: 3,
      ),
      ap(
        4,
        status: 'rejected',
        canRespond: false,
        direction: 'outgoing',
        from: 'ana',
      ),
      ap(5, type: 'onboarding', status: 'accepted', canRespond: false),
    ];

    test('AND across groups, OR inside one', () {
      var f = const ApprovalChipFilter()
          .toggle(ApprovalChipGroup.kind, 'form')
          .toggle(ApprovalChipGroup.kind, 'connection');
      expect(ids(ApprovalChips.apply(rows, f, ctx)), [1, 2, 3, 4]);
      f = f.toggle(ApprovalChipGroup.focus, 'waiting');
      expect(ids(ApprovalChips.apply(rows, f, ctx)), [1, 2, 3]);
      f = f.toggle(ApprovalChipGroup.form, 'leave');
      expect(ids(ApprovalChips.apply(rows, f, ctx)), [2]);
    });

    test('counts follow the other groups', () {
      final f = const ApprovalChipFilter().toggle(
        ApprovalChipGroup.focus,
        'waiting',
      );
      final views = ApprovalChips.viewsOf(rows, f, ctx);
      final kinds = views.firstWhere(
        (g) => g.first.group == ApprovalChipGroup.kind,
      );
      expect(
        {for (final v in kinds) v.key: v.count},
        {'connection': 1, 'form': 2},
      );
      final focus = views.firstWhere(
        (g) => g.first.group == ApprovalChipGroup.focus,
      );
      expect(focus.firstWhere((v) => v.key == 'waiting').count, 3);
    });

    test('form and stage chips come from the data', () {
      final views = ApprovalChips.viewsOf(
        rows,
        const ApprovalChipFilter(),
        ctx,
      );
      List<String> labels(ApprovalChipGroup g) => [
        for (final v in views.expand((x) => x).where((v) => v.group == g))
          v.label,
      ];
      expect(labels(ApprovalChipGroup.form), ['Leave', 'Expense']);
      expect(labels(ApprovalChipGroup.stage), ['Step 1 of 3', 'Step 2 of 3']);
      final none = ApprovalChips.viewsOf(
        [ap(1)],
        const ApprovalChipFilter(),
        ctx,
      );
      expect(
        none.expand((x) => x).where((v) => v.group == ApprovalChipGroup.form),
        isEmpty,
      );
    });

    test('a chip with no row is hidden unless it is on', () {
      final views = ApprovalChips.viewsOf(
        [ap(1)],
        const ApprovalChipFilter(),
        ctx,
      );
      final kinds = views
          .expand((x) => x)
          .where((v) => v.group == ApprovalChipGroup.kind);
      expect([for (final v in kinds) v.key], ['connection']);
      final on = ApprovalChips.viewsOf(
        [ap(1)],
        const ApprovalChipFilter().toggle(ApprovalChipGroup.kind, 'form'),
        ctx,
      );
      expect(on.expand((x) => x).any((v) => v.key == 'form' && v.isOn), isTrue);
    });

    test('clear empties everything', () {
      var f = const ApprovalChipFilter()
          .toggle(ApprovalChipGroup.focus, 'waiting')
          .toggle(ApprovalChipGroup.kind, 'form');
      f = f.toggle(ApprovalChipGroup.focus, 'waiting');
      expect(f.isOn(ApprovalChipGroup.focus, 'waiting'), isFalse);
      expect(f.isEmpty, isFalse);
      expect(f.clear().isEmpty, isTrue);
      expect(
        const ApprovalChipFilter()
            .toggle(ApprovalChipGroup.kind, 'form')
            .toggle(ApprovalChipGroup.kind, 'form')
            .isEmpty,
        isTrue,
      );
    });
  });

  group('which buttons show', () {
    List<ApprovalAction> a(Approval x) => ApprovalRules.actionsFor(x);
    test('a form: approve, decline, return, dismiss', () {
      expect(a(ap(1, type: 'submission')), [
        ApprovalAction.accept,
        ApprovalAction.reject,
        ApprovalAction.returnIt,
        ApprovalAction.ignore,
      ]);
    });
    test('any other kind: no Return', () {
      for (final t in [
        'onboarding',
        'associate',
        'handover',
        'group_invite',
        'host_transfer',
        'membership',
      ]) {
        expect(
          a(ap(1, type: t)),
          isNot(contains(ApprovalAction.returnIt)),
          reason: t,
        );
        expect(a(ap(1, type: t)), contains(ApprovalAction.accept), reason: t);
      }
    });
    test('no buttons without canRespond, and none once settled', () {
      expect(a(ap(1, canRespond: false)), isEmpty);
      expect(a(ap(1, direction: 'outgoing', canRespond: false)), isEmpty);
      for (final s in [
        'accepted',
        'rejected',
        'ignored',
        'returned',
        'expired',
      ]) {
        expect(a(ap(1, status: s)), isEmpty, reason: s);
      }
    });
  });
}
