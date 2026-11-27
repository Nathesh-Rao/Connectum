import '../../../data/models/approval.dart';
import 'approval_entries.dart';
import 'approval_pane.dart';
import 'inbox_approval_rows.dart';
import 'inbox_filter.dart';

/// The Approvals tab's filter panel as the person set it (the web's
/// `approvalsMode.js` `panel` and the ticked "Search in" entries). Immutable.
/// Memory only: it is never part of an [InboxFilter] and never saved in a
/// view.
///
/// [entries] are the entries the person ticked; none ticked means the
/// toggle's side of the chip, so pressing a chip or the toggle sets no
/// filter.
class ApprovalPanel {
  const ApprovalPanel({
    this.entries = const [],
    this.forms = const [],
    this.raisedBy = const [],
    this.approvers = const [],
    this.from = '',
    this.to = '',
    this.sort = InboxSort.latest,
    this.blocks = const [],
  });

  static const none = ApprovalPanel();

  final List<ApprovalEntry> entries;
  final List<String> forms;
  final List<String> raisedBy;
  final List<String> approvers;

  /// `yyyy-mm-dd` or ''.
  final String from;
  final String to;
  final String sort;
  final List<InboxBlock> blocks;

  ApprovalPanel copyWith({
    List<ApprovalEntry>? entries,
    List<String>? forms,
    List<String>? raisedBy,
    List<String>? approvers,
    String? from,
    String? to,
    String? sort,
    List<InboxBlock>? blocks,
  }) => ApprovalPanel(
    entries: entries ?? this.entries,
    forms: forms ?? this.forms,
    raisedBy: raisedBy ?? this.raisedBy,
    approvers: approvers ?? this.approvers,
    from: from ?? this.from,
    to: to ?? this.to,
    sort: sort ?? this.sort,
    blocks: blocks ?? this.blocks,
  );

  /// The blocks that say something.
  List<InboxBlock> get activeBlocks => [
    for (final b in blocks)
      if (b.isActive) b,
  ];

  /// How many lines say something (what the filter button's badge counts):
  /// the entries ticked (one line), the forms, the people, the dates, the
  /// order and each block. A chip or the toggle counts for nothing.
  int get count =>
      (entries.isEmpty ? 0 : 1) +
      (forms.isEmpty ? 0 : 1) +
      (raisedBy.isEmpty ? 0 : 1) +
      (approvers.isEmpty ? 0 : 1) +
      (from.isEmpty && to.isEmpty ? 0 : 1) +
      (sort == InboxSort.latest ? 0 : 1) +
      activeBlocks.length;

  bool get isEmpty => count == 0;
}

/// One field a condition can use: the caption a request card shows and how
/// its values read.
class ApprovalField {
  const ApprovalField(this.caption, this.kind);

  final String caption;

  /// `text`, `number` or `date`.
  final String kind;
}

/// The words of the Sort line (the four orders that fit requests).
class ApprovalSorts {
  ApprovalSorts._();

  static const choices = [
    (InboxSort.latest, 'Latest'),
    (InboxSort.oldest, 'Oldest'),
    (InboxSort.asc, 'A to Z'),
    (InboxSort.desc, 'Z to A'),
  ];
}

/// The rules of the Approvals panel, read on what the server returned
/// (`req.list`, `req.team`): who may see a request is the server's decision.
/// Pure. A port of `approvalFilters.js` / `approvalNarrow.js` /
/// `approvalsMode.js`.
class ApprovalPanelRules {
  ApprovalPanelRules._();

  /// The most summary fields a request card carries.
  static const maxSummaryFields = 8;

  // ---- Search in -------------------------------------------------------------

  /// Every entry the chip offers: the person's own, then the team's (only a
  /// person with reports is offered those).
  static List<ApprovalEntry> offered(ApprovalPrimary chip, bool hasTeam) => [
    ...ApprovalEntries.entriesOf(chip, ApprovalSide.me),
    if (hasTeam) ...ApprovalEntries.entriesOf(chip, ApprovalSide.team),
  ];

  /// The side a choice is: all the person's own, or all the team's; null when
  /// nothing is chosen or the choice is mixed.
  static ApprovalSide? sideOf(Iterable<ApprovalEntry> entries) {
    final sides = {for (final e in entries) e.side};
    return sides.length == 1 ? sides.first : null;
  }

  /// The entries the list is cut by: the ones ticked (only ones the chip
  /// has), else the toggle's side of the chip.
  static List<ApprovalEntry> effective(
    ApprovalPrimary chip,
    ApprovalSide side,
    List<ApprovalEntry> ticked, {
    required bool hasTeam,
  }) {
    final known = offered(chip, hasTeam);
    final picked = [
      for (final e in known)
        if (ticked.contains(e)) e,
    ];
    return picked.isNotEmpty
        ? picked
        : ApprovalEntries.entriesOf(chip, hasTeam ? side : ApprovalSide.me);
  }

  /// What "Search in" says in grey while nothing is ticked: the entries the
  /// toggle is showing.
  static String usualText(
    ApprovalPrimary chip,
    ApprovalSide side, {
    required bool hasTeam,
  }) => [
    for (final e in ApprovalEntries.entriesOf(
      chip,
      hasTeam ? side : ApprovalSide.me,
    ))
      e.label,
  ].join(', ');

  static bool inEntries(
    Approval a,
    Iterable<ApprovalEntry> entries,
    ApprovalWho who,
  ) => entries.any((e) => ApprovalEntries.inEntry(a, e, who));

  // ---- the people lines ---------------------------------------------------------

  static String _lower(String s) => s.trim().toLowerCase();

  /// Who raised the requests (`fromUser`), each once, lower case.
  static List<String> askers(Iterable<Approval> rows) => {
    for (final a in rows)
      if (_lower(a.fromUser).isNotEmpty) _lower(a.fromUser),
  }.toList();

  /// Who must answer them (`approvers`), each once, lower case.
  static List<String> approversOf(Iterable<Approval> rows) => {
    for (final a in rows)
      for (final u in a.approvers)
        if (_lower(u).isNotEmpty) _lower(u),
  }.toList();

  // ---- the forms (Data) ---------------------------------------------------------

  /// Form id -> caption of the forms the requests are of.
  static Map<String, String> formsOf(Iterable<Approval> rows) {
    final out = <String, String>{};
    for (final a in rows) {
      if (a.formId.isEmpty) continue;
      final known = out[a.formId];
      if (known == null || (known == a.formId && a.caption.isNotEmpty)) {
        out[a.formId] = a.caption.isNotEmpty ? a.caption : a.formId;
      }
    }
    return out;
  }

  // ---- the fields of the Advanced filter ----------------------------------------

  /// The fields of a form a condition may use: the captions of the summary
  /// lines its requests carry (at most [maxSummaryFields] a request), in the
  /// order first seen, each with the kind its values read as.
  static List<ApprovalField> fieldsOf(Iterable<Approval> rows, String formId) {
    final values = <String, List<String>>{};
    for (final a in rows) {
      if (a.formId != formId) continue;
      for (final l in a.lines.take(maxSummaryFields)) {
        if (l.caption.isEmpty) continue;
        values.putIfAbsent(l.caption, () => []).add(l.value.trim());
      }
    }
    return [
      for (final e in values.entries)
        ApprovalField(e.key, kindOfValues(e.value)),
    ];
  }

  /// The kind the values of one field read as: `number` when every value
  /// there is a number, `date` when every one is a day, else `text` (also
  /// when there is no value to tell by).
  static String kindOfValues(Iterable<String> values) {
    final filled = [
      for (final v in values)
        if (v.trim().isNotEmpty) v,
    ];
    if (filled.isEmpty) return 'text';
    if (filled.every((v) => numberOf(v) != null)) return 'number';
    if (filled.every((v) => dayOf(v) != null)) return 'date';
    return 'text';
  }

  static final _grouped = RegExp(r'^-?\d{1,3}(,\d{3})+(\.\d+)?$');

  /// A number as a card shows it (`1200`, `-3.5`, `1,200`); null when it is
  /// not one.
  static double? numberOf(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(_grouped.hasMatch(t) ? t.replaceAll(',', '') : t);
    return v != null && v.isFinite ? v : null;
  }

  static final _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');
  static final _dmy = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$');

  /// A day as a card shows it (`2026-03-09...`, `09/03/2026`, `09-03-2026`)
  /// as `yyyy-mm-dd`; null when it is not one.
  static String? dayOf(String s) {
    final t = s.trim();
    String two(String x) => x.padLeft(2, '0');
    final iso = _iso.firstMatch(t);
    if (iso != null) {
      return _valid(iso[1]!, iso[2]!, iso[3]!)
          ? '${iso[1]}-${iso[2]}-${iso[3]}'
          : null;
    }
    final dmy = _dmy.firstMatch(t);
    if (dmy != null && _valid(dmy[3]!, two(dmy[2]!), two(dmy[1]!))) {
      return '${dmy[3]}-${two(dmy[2]!)}-${two(dmy[1]!)}';
    }
    return null;
  }

  static bool _valid(String y, String m, String d) {
    final mm = int.parse(m);
    final dd = int.parse(d);
    return mm >= 1 && mm <= 12 && dd >= 1 && dd <= 31;
  }

  /// The answer a request carries for a field: the value of the summary line
  /// with that caption, '' when it carries none.
  static String answerOf(Approval a, String caption) {
    for (final l in a.lines.take(maxSummaryFields)) {
      if (l.caption == caption) return l.value.trim();
    }
    return '';
  }

  /// One condition on an answer. A value that is not a number (or a day)
  /// never passes a number (or date) test (`conditionHolds`).
  static bool conditionHolds(String answer, InboxCondition c, String kind) {
    final have = answer.trim();
    if (c.op == 'empty') return have.isEmpty;
    if (c.op == 'notempty') return have.isNotEmpty;
    if (have.isEmpty) return false;
    if (kind == 'number') {
      final a = numberOf(have);
      final x = numberOf(c.value);
      if (a == null || x == null) return false;
      final y = numberOf(c.value2);
      return switch (c.op) {
        'eq' => a == x,
        'ne' => a != x,
        'gt' => a > x,
        'gte' => a >= x,
        'lt' => a < x,
        'lte' => a <= x,
        'between' => y != null && a >= (x < y ? x : y) && a <= (x < y ? y : x),
        _ => false,
      };
    }
    if (kind == 'date') {
      final a = dayOf(have);
      final x = dayOf(c.value);
      if (a == null || x == null) return false;
      final y = dayOf(c.value2);
      return switch (c.op) {
        'eq' => a == x,
        'ne' => a != x,
        'gt' => a.compareTo(x) > 0,
        'gte' => a.compareTo(x) >= 0,
        'lt' => a.compareTo(x) < 0,
        'lte' => a.compareTo(x) <= 0,
        'between' =>
          y != null &&
              a.compareTo(x.compareTo(y) < 0 ? x : y) >= 0 &&
              a.compareTo(x.compareTo(y) < 0 ? y : x) <= 0,
        _ => false,
      };
    }
    final a = have.toLowerCase();
    final x = c.value.trim().toLowerCase();
    return switch (c.op) {
      'contains' => a.contains(x),
      'eq' => a == x,
      'ne' => a != x,
      'starts' => a.startsWith(x),
      'ends' => a.endsWith(x),
      _ => false,
    };
  }

  /// Does one block hold for a request? A block names forms; conditions only
  /// count in a block of one form, the ready ones, joined from the left.
  static bool _blockHolds(InboxBlock b, Approval a, Map<String, String> kinds) {
    if (b.forms.isNotEmpty && !b.forms.contains(a.formId)) return false;
    if (b.forms.length != 1) return true;
    var holds = true;
    var i = 0;
    for (final c in b.conditions.where((c) => c.isReady)) {
      final one = conditionHolds(
        answerOf(a, c.field),
        c,
        kinds['${b.id}|${c.id}'] ?? 'text',
      );
      holds = i == 0 ? one : (c.join == 'or' ? holds || one : holds && one);
      i++;
    }
    return holds;
  }

  // ---- narrowing ----------------------------------------------------------------

  static final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static DateTime? _dayStart(String iso) {
    if (!_day.hasMatch(iso)) return null;
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  static bool _isInDays(int ts, String fromIso, String toIso) {
    final from = _dayStart(fromIso);
    final to = _dayStart(toIso);
    if (from == null && to == null) return true;
    if (ts <= 0) return false;
    final at = DateTime.fromMillisecondsSinceEpoch(ts);
    if (from != null && at.isBefore(from)) return false;
    if (to != null && !at.isBefore(to.add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  /// The requests that pass the panel's lines (forms, people, dates,
  /// Advanced) in the order Sort says. The entries are not applied here.
  /// [pool] is every request read, to tell the kind of a field by (defaults
  /// to [rows]); [ignoreForms] leaves the Data line out, for its own counts.
  static List<Approval> narrow(
    Iterable<Approval> rows,
    ApprovalPanel p, {
    Iterable<Approval>? pool,
    bool ignoreForms = false,
  }) {
    final raised = {for (final u in p.raisedBy) _lower(u)};
    final asked = {for (final u in p.approvers) _lower(u)};
    final blocks = p.activeBlocks;
    final all = (pool ?? rows).toList();
    final kinds = <String, String>{
      for (final b in blocks)
        if (b.forms.length == 1)
          for (final c in b.conditions)
            if (c.isReady)
              '${b.id}|${c.id}':
                  fieldsOf(all, b.forms.single)
                      .where((f) => f.caption == c.field)
                      .map((f) => f.kind)
                      .firstOrNull ??
                  'text',
    };
    final kept = [
      for (final a in rows)
        if (_isInDays(a.createdTs, p.from, p.to) &&
            (ignoreForms || p.forms.isEmpty || p.forms.contains(a.formId)) &&
            (raised.isEmpty || raised.contains(_lower(a.fromUser))) &&
            (asked.isEmpty ||
                a.approvers.any((u) => asked.contains(_lower(u)))) &&
            (blocks.isEmpty || blocks.any((b) => _blockHolds(b, a, kinds))))
          a,
    ];
    return InboxApprovalRows.sorted(kept, p.sort);
  }

  /// How many requests each form has in [entries], under every line of the
  /// panel except the Data line itself (the Data chips' numbers).
  static Map<String, int> formCounts(
    Iterable<Approval> rows,
    ApprovalPanel p,
    Iterable<ApprovalEntry> entries,
    ApprovalWho who,
  ) {
    final out = <String, int>{};
    final cut = narrow(
      [
        for (final a in rows)
          if (ApprovalPane.isListed(a) && inEntries(a, entries, who)) a,
      ],
      p,
      pool: rows,
      ignoreForms: true,
    );
    for (final a in cut) {
      if (a.formId.isNotEmpty) out[a.formId] = (out[a.formId] ?? 0) + 1;
    }
    return out;
  }
}
