import '../../../data/models/approval.dart';
import 'approval_entries.dart';
import 'approval_pane.dart';

/// The SECONDARY chip groups of the Approvals tab (the primary chips All,
/// Pending, Approved, Requests and Rejected are [ApprovalEntries]). Chips of
/// one group combine with OR, the groups with AND.
enum ApprovalChipGroup { direction, focus, kind, form, stage }

/// What a request is, in the words of the chips (the web's `KIND`). Every
/// `type` is in exactly one kind; an unknown one (`wizard` included) is
/// [other].
enum ApprovalKind {
  signUp('signup', 'Sign-up'),
  connection('connection', 'Connection'),
  introduction('introduction', 'Introduction'),
  groupInvite('group', 'Group invitation'),
  transfer('transfer', 'Transfer'),
  form('form', 'Form'),
  other('other', 'Other');

  const ApprovalKind(this.key, this.label);

  final String key;
  final String label;
}

/// The viewer and the time the chip rules need.
class ApprovalChipContext {
  const ApprovalChipContext({this.me = '', required this.now});

  /// The signed-in username, lower case; '' when unknown.
  final String me;
  final DateTime now;
}

/// One chip as drawn: its key in the group, its words, how many rows it holds
/// with the other groups applied, and whether it is on.
class ApprovalChipView {
  const ApprovalChipView({
    required this.group,
    required this.key,
    required this.label,
    required this.count,
    required this.isOn,
  });

  final ApprovalChipGroup group;
  final String key;
  final String label;
  final int count;
  final bool isOn;
}

/// The chips the Approvals tab holds and which are on. Pure and immutable.
/// Nothing here is saved in a view.
class ApprovalChipFilter {
  const ApprovalChipFilter([this.on = const {}]);

  final Map<ApprovalChipGroup, Set<String>> on;

  static const waiting = 'waiting';
  static const escalated = 'escalated';
  static const fromMe = 'from_me';
  static const notFromMe = 'not_from_me';
  static const toMe = 'to_me';
  static const notToMe = 'not_to_me';

  bool get isEmpty => on.values.every((s) => s.isEmpty);

  bool isOn(ApprovalChipGroup g, String key) => on[g]?.contains(key) ?? false;

  /// Turns one chip on or off.
  ApprovalChipFilter toggle(ApprovalChipGroup g, String key) {
    final next = {
      for (final e in on.entries) e.key: {...e.value},
    };
    final set = next.putIfAbsent(g, () => <String>{});
    if (!set.remove(key)) set.add(key);
    if (set.isEmpty) next.remove(g);
    return ApprovalChipFilter(next);
  }

  ApprovalChipFilter clear() => const ApprovalChipFilter();

  /// Is [a] kept: every group with a chip on holds it (OR inside the group).
  /// [except] leaves one group out, for that group's own counts.
  bool matches(
    Approval a,
    ApprovalChipContext ctx, {
    ApprovalChipGroup? except,
  }) {
    for (final e in on.entries) {
      if (e.key == except || e.value.isEmpty) continue;
      if (!e.value.any((k) => ApprovalChips.inChip(a, e.key, k, ctx))) {
        return false;
      }
    }
    return true;
  }
}

/// The chips of the Approvals tab: how a request falls in each. Pure.
class ApprovalChips {
  ApprovalChips._();

  static ApprovalKind kindOf(Approval a) => switch (a.type) {
    'onboarding' => ApprovalKind.signUp,
    'membership' || 'associate' => ApprovalKind.connection,
    'handover' => ApprovalKind.introduction,
    'group_invite' => ApprovalKind.groupInvite,
    'host_transfer' => ApprovalKind.transfer,
    'submission' => ApprovalKind.form,
    _ => ApprovalKind.other,
  };

  /// "Sent by me" of the entries: the person raised it (the server says
  /// `outgoing`).
  static bool isFromMe(Approval a, ApprovalChipContext ctx) => a.isOutgoing;

  /// "Sent to me" of the entries: the person is an approver (`incoming`) or
  /// may answer it (an administrator, for example).
  static bool isToMe(Approval a) =>
      a.isIncoming || ApprovalEntries.waitsForMe(a);

  /// "Step 2 of 3": only a form with more than one step.
  static String? stageKey(Approval a) {
    final s = a.stage;
    final n = a.stages;
    if (!a.isSubmission || s == null || n == null || n < 2) return null;
    return '$s/$n';
  }

  static String stageLabel(String key) {
    final p = key.split('/');
    return p.length == 2 ? 'Step ${p[0]} of ${p[1]}' : key;
  }

  /// Does [a] belong to chip [key] of group [g]?
  static bool inChip(
    Approval a,
    ApprovalChipGroup g,
    String key,
    ApprovalChipContext ctx,
  ) => switch (g) {
    ApprovalChipGroup.direction => switch (key) {
      ApprovalChipFilter.fromMe => isFromMe(a, ctx),
      ApprovalChipFilter.notFromMe => !isFromMe(a, ctx),
      ApprovalChipFilter.toMe => isToMe(a),
      ApprovalChipFilter.notToMe => !isToMe(a),
      _ => false,
    },
    ApprovalChipGroup.focus => switch (key) {
      ApprovalChipFilter.waiting => ApprovalPane.isWaitingForMe(a),
      ApprovalChipFilter.escalated => ApprovalPane.isEscalated(a, ctx.now),
      _ => false,
    },
    ApprovalChipGroup.kind => kindOf(a).key == key,
    ApprovalChipGroup.form => a.formId.isNotEmpty && a.formId == key,
    ApprovalChipGroup.stage => stageKey(a) == key,
  };

  /// The rows the chips keep.
  static List<Approval> apply(
    Iterable<Approval> rows,
    ApprovalChipFilter f,
    ApprovalChipContext ctx,
  ) => [
    for (final a in rows)
      if (f.matches(a, ctx)) a,
  ];

  static const _directionLabels = [
    (ApprovalChipFilter.fromMe, 'From me'),
    (ApprovalChipFilter.notFromMe, 'Not from me'),
    (ApprovalChipFilter.toMe, 'To me'),
    (ApprovalChipFilter.notToMe, 'Not to me'),
  ];

  static const _focusLabels = [
    (ApprovalChipFilter.waiting, 'Waiting for you'),
    (ApprovalChipFilter.escalated, 'Escalated'),
  ];

  /// The chips to draw, group by group, with live counts: a chip counts the
  /// rows that hold it and pass every OTHER group's chips. A chip shows only
  /// with a row, or while it is on. [rows] are the rows of the primary chip
  /// and side the search keeps.
  static List<List<ApprovalChipView>> viewsOf(
    List<Approval> rows,
    ApprovalChipFilter f,
    ApprovalChipContext ctx,
  ) {
    int count(ApprovalChipGroup g, String key) => rows
        .where((a) => f.matches(a, ctx, except: g) && inChip(a, g, key, ctx))
        .length;

    ApprovalChipView view(ApprovalChipGroup g, String key, String label) =>
        ApprovalChipView(
          group: g,
          key: key,
          label: label,
          count: count(g, key),
          isOn: f.isOn(g, key),
        );

    List<ApprovalChipView> shown(Iterable<ApprovalChipView> v) => [
      for (final c in v)
        if (c.count > 0 || c.isOn) c,
    ];

    final forms = <String, String>{};
    final stages = <String>{};
    for (final a in rows) {
      if (a.formId.isNotEmpty) {
        forms.putIfAbsent(
          a.formId,
          () => a.caption.isNotEmpty ? a.caption : a.formId,
        );
      }
      final s = stageKey(a);
      if (s != null) stages.add(s);
    }
    final stageKeys = stages.toList()
      ..sort((x, y) {
        final a = x.split('/').map(int.parse).toList();
        final b = y.split('/').map(int.parse).toList();
        return a[1] != b[1] ? a[1].compareTo(b[1]) : a[0].compareTo(b[0]);
      });
    // A chip that is on stays even when it has no row any more, so it can be
    // turned off.
    for (final k in f.on[ApprovalChipGroup.form] ?? const <String>{}) {
      forms.putIfAbsent(k, () => k);
    }
    for (final k in f.on[ApprovalChipGroup.stage] ?? const <String>{}) {
      if (!stageKeys.contains(k)) stageKeys.add(k);
    }

    return [
      shown([
        for (final d in _directionLabels)
          view(ApprovalChipGroup.direction, d.$1, d.$2),
      ]),
      shown([
        for (final d in _focusLabels) view(ApprovalChipGroup.focus, d.$1, d.$2),
      ]),
      shown([
        for (final k in ApprovalKind.values)
          view(ApprovalChipGroup.kind, k.key, k.label),
      ]),
      shown([
        for (final e in forms.entries)
          view(ApprovalChipGroup.form, e.key, e.value),
      ]),
      shown([
        for (final k in stageKeys)
          view(ApprovalChipGroup.stage, k, stageLabel(k)),
      ]),
    ].where((g) => g.isNotEmpty).toList();
  }
}
