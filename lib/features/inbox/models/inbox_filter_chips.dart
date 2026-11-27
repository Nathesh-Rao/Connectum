import 'inbox_filter.dart';

/// One removable chip of the Records filter row: what it says, and the filter
/// that is left once it is removed.
class InboxFilterChip {
  const InboxFilterChip({
    required this.id,
    required this.label,
    required this.removed,
  });

  final String id;
  final String label;

  /// The filter without this chip's part.
  final InboxFilter removed;
}

/// The chips of an [InboxFilter], one per filter that says something, in the
/// order of the filter panel. Pure.
class InboxFilterChips {
  InboxFilterChips._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const _peopleLabels = {
    'createdBy': 'Created by',
    'sentBy': 'Sent by',
    'sentTo': 'Sent to',
    'taggedTo': 'Tagged to',
  };

  /// "2026-11-05" as "5 Nov 2026"; anything else as it is.
  static String dayLabel(String day) {
    final p = day.split('-');
    final m = p.length == 3 ? int.tryParse(p[1]) : null;
    final d = p.length == 3 ? int.tryParse(p[2]) : null;
    if (m == null || d == null || m < 1 || m > 12) return day;
    return '$d ${_months[m - 1]} ${p[0]}';
  }

  /// The chips for [f]. [formName] and [personName] say how a form and a
  /// person are shown.
  static List<InboxFilterChip> of(
    InboxFilter f, {
    required String Function(String id) formName,
    required String Function(String user) personName,
  }) {
    String person(String u) => u == 'me' ? 'Me' : personName(u);
    List<String> without(List<String> all, String one) => [
      for (final x in all)
        if (x != one) x,
    ];
    return [
      for (final w in f.wheres)
        if (w != InboxWhere.all)
          InboxFilterChip(
            id: 'where-$w',
            label: InboxWhere.labels[w] ?? w,
            removed: f.copyWith(wheres: without(f.wheres, w)),
          ),
      for (final id in f.forms)
        InboxFilterChip(
          id: 'form-$id',
          label: formName(id),
          removed: f.copyWith(forms: without(f.forms, id)),
        ),
      for (final key in inboxPeopleKeys)
        for (final u in f.peopleOf(key))
          InboxFilterChip(
            id: '$key-$u',
            label: '${_peopleLabels[key]} ${person(u)}',
            removed: f.withPeople(key, without(f.peopleOf(key), u)),
          ),
      if (f.hasDays)
        InboxFilterChip(
          id: 'days',
          label: f.from.isNotEmpty && f.to.isNotEmpty
              ? '${dayLabel(f.from)} to ${dayLabel(f.to)}'
              : f.from.isNotEmpty
              ? 'From ${dayLabel(f.from)}'
              : 'Until ${dayLabel(f.to)}',
          removed: f.copyWith(from: '', to: ''),
        ),
      if (f.status.isNotEmpty)
        InboxFilterChip(
          id: 'status',
          label: f.status == InboxSort.open ? 'Open only' : 'Closed only',
          removed: f.copyWith(status: ''),
        ),
      if (f.sort != InboxSort.latest)
        InboxFilterChip(
          id: 'sort',
          label:
              'Sort: ${InboxSort.choices.where((c) => c.$1 == f.sort).map((c) => c.$2).firstOrNull ?? f.sort}',
          removed: f.copyWith(sort: InboxSort.latest),
        ),
      for (final b in f.blocks)
        if (b.isActive)
          InboxFilterChip(
            id: 'block-${b.id}',
            label: _blockLabel(b, formName, person),
            removed: f.copyWith(
              blocks: [
                for (final x in f.blocks)
                  if (x.id != b.id) x,
              ],
            ),
          ),
      if (f.approvalPick.isNotEmpty)
        InboxFilterChip(
          id: 'approval',
          label:
              'Approval: ${f.approvalPick.map((a) => InboxApprovalAnswer.labels[a] ?? a).join(', ')}',
          removed: f.copyWith(approvalPick: const []),
        ),
    ];
  }

  static String _blockLabel(
    InboxBlock b,
    String Function(String) formName,
    String Function(String) person,
  ) {
    final parts = [
      if (b.forms.isNotEmpty) b.forms.map(formName).join(', '),
      if (b.createdBy.isNotEmpty) 'by ${b.createdBy.map(person).join(', ')}',
      if (b.sentBy.isNotEmpty) 'sent by ${b.sentBy.map(person).join(', ')}',
      if (b.sentTo.isNotEmpty) 'sent to ${b.sentTo.map(person).join(', ')}',
      for (final c in b.conditions.where((c) => c.isReady))
        [
          c.field,
          InboxOps.text
                  .followedBy(InboxOps.number)
                  .followedBy(InboxOps.date)
                  .where((o) => o.$1 == c.op)
                  .map((o) => o.$2)
                  .firstOrNull ??
              c.op,
          if (InboxOps.needsValue(c.op)) c.value,
          if (c.op == 'between') 'and ${c.value2}',
        ].join(' '),
    ];
    return 'Advanced: ${parts.join(' · ')}';
  }
}
