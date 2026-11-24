import '../../../data/models/approval.dart';
import 'approval_pane.dart';
import 'approval_reducer.dart';
import 'inbox_filter.dart';
import 'inbox_sort.dart';

/// How the approval list takes part in the Inbox list: a port of the web's
/// `HashInboxModal.jsx` (`approvalRows`, `escalatedApprovals`, `stage`,
/// `approvalFormCounts`). Pure; the approvals are the ones of the shared
/// list, never a read of their own.
///
/// * One approval entry in "Search in" (Approvals, Pending my approvals,
///   Approved, Rejected) is a list of its own (the web's `stage`): no records
///   are asked, and Data, Date, Sort and the search apply.
/// * Several entries (or none, with the Advanced ticks) is the records list
///   with the approvals that match drawn under it (`approvalRows`): only Data
///   and the search apply; the people lines, Date, Sort and Open / Closed are
///   the records' own.
/// * Escalations adds the approvals that have waited for the person longer
///   than three days, under the records (`escalatedApprovals`), whatever the
///   other lines say.
class InboxApprovalRows {
  const InboxApprovalRows(this.filter);

  final InboxFilter filter;

  static const _states = {
    'any': [
      ApprovalState.pending,
      ApprovalState.approved,
      ApprovalState.rejected,
      ApprovalState.other,
    ],
    'pending': [ApprovalState.pending],
    'approved': [ApprovalState.approved],
    'rejected': [ApprovalState.rejected],
  };

  List<String> get _wheres => filter.wheres;

  bool get isMulti => _wheres.length > 1;

  /// The answer the one approval entry holds (`any`, `pending`, `approved`,
  /// `rejected`); '' when "Search in" is not one approval entry.
  String get stage =>
      _wheres.length == 1 ? InboxWhere.stageOf[_wheres.first] ?? '' : '';

  /// Is the choice one approval entry (a list of approvals alone)?
  bool get isStageList => stage.isNotEmpty;

  /// Is the choice only approval entries (the records are not asked: the
  /// web's `recordsOff`)?
  bool get isApprovalsOnly =>
      _wheres.isNotEmpty && _wheres.every(InboxWhere.stageOf.containsKey);

  /// Does "Search in" hold an approval entry?
  bool get hasApprovalEntry => _wheres.any(InboxWhere.stageOf.containsKey);

  /// The records list is the web's "data" folder: no entry, or several (a
  /// single Me / My Team is only the switch).
  bool get _isDataFolder =>
      _wheres.isEmpty ||
      isMulti ||
      _wheres.first == InboxWhere.me ||
      _wheres.first == InboxWhere.team;

  bool get hasEscalations => _wheres.contains(InboxWhere.escalations);

  /// The forms the filter names: the Data line and the Advanced blocks.
  Set<String> get dataForms => {
    ...filter.forms,
    for (final b in filter.blocks) ...b.forms,
  };

  /// Is a form named that has an approval request? Only then are the Advanced
  /// ticks in force (the web drops them the moment it is not).
  bool hasApprovalForm(Iterable<Approval> all) {
    final named = dataForms;
    return named.isNotEmpty &&
        all.any(
          (a) =>
              ApprovalPane.isListed(a) &&
              a.formId.isNotEmpty &&
              named.contains(a.formId),
        );
  }

  /// Can the approvals be part of the list at all (before they are read)?
  bool get wantsApprovals =>
      isStageList ||
      hasEscalations ||
      (_isDataFolder && (hasApprovalEntry || filter.approvalPick.isNotEmpty));

  Set<ApprovalState> _answers(Iterable<Approval> all) {
    final picks = hasApprovalForm(all) ? filter.approvalPick : const [];
    return {
      for (final p in picks) ?_stateOfPick(p),
      if (isMulti)
        for (final w in _wheres) ...?_states[InboxWhere.stageOf[w]],
    };
  }

  static ApprovalState? _stateOfPick(String p) => switch (p) {
    InboxApprovalAnswer.pending => ApprovalState.pending,
    InboxApprovalAnswer.approved => ApprovalState.approved,
    InboxApprovalAnswer.rejected => ApprovalState.rejected,
    _ => null,
  };

  /// The cards of the approvals, newest first: the list of one entry, or the
  /// matching ones under the records, then the escalated ones the records
  /// do not hold already.
  List<Approval> cards(
    Iterable<Approval> all, {
    String query = '',
    String Function(Approval)? nameOf,
    required DateTime now,
  }) {
    bool matches(Approval a) =>
        ApprovalPane.matches(a, query, personName: nameOf?.call(a) ?? '');
    if (isStageList) {
      return sorted(stageRows(all).where(matches), filter.sort);
    }
    final rows = [if (_isDataFolder) ...mixedRows(all).where(matches)];
    if (!hasEscalations) return rows;
    final seen = {for (final a in rows) a.id};
    return [
      ...rows,
      for (final a in escalated(all, now))
        if (seen.add(a.id)) a,
    ];
  }

  /// The approvals of the one entry (the web's `stage`), cut to the forms
  /// named and to the days chosen. Pending holds only those waiting for the
  /// person. [ignoreForms] is for the Data line's own counts.
  List<Approval> stageRows(Iterable<Approval> all, {bool ignoreForms = false}) {
    final states = _states[stage] ?? const [];
    final forms = ignoreForms ? const <String>{} : dataForms;
    return [
      for (final a in ApprovalReducer.sorted(all))
        if (ApprovalPane.isListed(a) &&
            states.contains(ApprovalPane.stateOf(a)) &&
            (stage != 'pending' || a.canRespond) &&
            (forms.isEmpty || forms.contains(a.formId)) &&
            _isInDays(a.createdTs))
          a,
    ];
  }

  /// The approvals under the records (the web's `approvalRows`): the answers
  /// of the entries and of the ticks, cut to the forms named. A pending one
  /// that is not the person's to answer is listed only when Approvals or the
  /// Pending tick asks for it.
  List<Approval> mixedRows(Iterable<Approval> all, {bool ignoreForms = false}) {
    final answers = _answers(all);
    if (!_isDataFolder || answers.isEmpty) return const [];
    final forms = ignoreForms ? const <String>{} : dataForms;
    final isPendingAsked =
        !isMulti ||
        (hasApprovalForm(all) &&
            filter.approvalPick.contains(InboxApprovalAnswer.pending)) ||
        _wheres.contains(InboxWhere.allApprovals);
    return [
      for (final a in ApprovalReducer.sorted(all))
        if (ApprovalPane.isListed(a) &&
            (forms.isEmpty || forms.contains(a.formId)) &&
            answers.contains(ApprovalPane.stateOf(a)) &&
            (ApprovalPane.stateOf(a) != ApprovalState.pending ||
                isPendingAsked ||
                a.canRespond))
          a,
    ];
  }

  /// Waiting for the person longer than three days (`escalatedApprovals`),
  /// newest first.
  List<Approval> escalated(Iterable<Approval> all, DateTime now) => [
    for (final a in ApprovalReducer.sorted(all))
      if (ApprovalPane.isEscalated(a, now)) a,
  ];

  /// How many approvals each form has under the panel as it stands, for the
  /// Data list (`approvalFormCounts`): the cards of the approval entries
  /// chosen, whatever form is named. Empty when no approval entry is chosen.
  Map<String, int> formCounts(Iterable<Approval> all) {
    if (!hasApprovalEntry) return const {};
    final rows = isStageList
        ? stageRows(all, ignoreForms: true)
        : mixedRows(all, ignoreForms: true);
    final out = <String, int>{};
    for (final a in rows) {
      if (a.formId.isNotEmpty) out[a.formId] = (out[a.formId] ?? 0) + 1;
    }
    return out;
  }

  static final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  static DateTime? _dayStart(String iso) {
    if (!_day.hasMatch(iso)) return null;
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// Is the time inside the days chosen (`inTiming`: either end may be left
  /// open, the last day counts to its end)? A request with no time does not
  /// pass a cut.
  bool _isInDays(int ts) {
    final from = _dayStart(filter.from);
    final to = _dayStart(filter.to);
    if (from == null && to == null) return true;
    if (ts <= 0) return false;
    final at = DateTime.fromMillisecondsSinceEpoch(ts);
    if (from != null && at.isBefore(from)) return false;
    if (to != null && !at.isBefore(to.add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  /// The order Sort says (`sortRows`): latest or oldest by time, A to Z or
  /// Z to A by the card's title; a tie keeps the newest first.
  static List<Approval> sorted(Iterable<Approval> rows, String sort) {
    int time(Approval a) => a.createdTs > 0 ? a.createdTs : 0;
    int newest(Approval a, Approval b) => time(b) - time(a);
    int Function(Approval, Approval) by = newest;
    if (sort == InboxSort.oldest) {
      by = (a, b) => time(a) > 0 && time(b) > 0
          ? time(a) - time(b)
          : time(b) > 0
          ? 1
          : time(a) > 0
          ? -1
          : 0;
    } else if (sort == InboxSort.asc || sort == InboxSort.desc) {
      final dir = sort == InboxSort.asc ? 1 : -1;
      by = (a, b) {
        final c =
            dir *
            naturalCompare(ApprovalPane.titleOf(a), ApprovalPane.titleOf(b));
        return c != 0 ? c : newest(a, b);
      };
    }
    final list = rows.toList();
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final c = by(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }
}
