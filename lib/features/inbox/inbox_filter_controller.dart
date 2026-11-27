import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../core/log/app_log.dart';
import '../../core/log/safe.dart';
import '../../data/models/approval.dart';
import '../../data/repositories/inbox_field_kinds.dart';
import '../../data/repositories/inbox_repository.dart';
import '../../data/socket/socket_service.dart';
import 'inbox_approvals_controller.dart';
import 'models/inbox_approval_rows.dart';
import 'models/inbox_filter.dart';
import 'models/inbox_page.dart';
import 'models/inbox_query.dart';

/// One entry of a list in the panel.
class InboxChoice {
  const InboxChoice(this.id, this.label);

  final String id;
  final String label;
}

class _Answer {
  const _Answer(this.group, this.key, this.facets);

  /// The "Search in" the answer is for; an answer of another group is never
  /// shown.
  final String group;

  /// The ask as it was sent; the answer is fresh while it equals the ask of
  /// the panel as it stands.
  final String key;
  final InboxFacets facets;
}

/// The Inbox filter panel (`InboxFilterFab.jsx`, `useFormCounts.js`): the
/// draft, and what its lists offer. Nothing applies until [apply]; a draft
/// left without it is dropped. Facets are read only while the panel is open
/// (the controller lives as long as the sheet), 150 ms after the last change,
/// and an answer is shown only for its own "Search in" group.
class InboxFilterController extends GetxController {
  InboxFilterController({
    required this.inbox,
    required InboxFilter initial,
    required this.baseWhere,
    required this.isTeamShown,
    required Map<String, String> forms,
    required this.onApply,
    required this.onClear,
    this.fieldKinds,
    this.approvals,
    this.wait = const Duration(milliseconds: 150),
    this.isSample = false,
  }) : draft = Rx<InboxFilter>(
         initial.wheres.isEmpty
             ? initial.copyWith(wheres: [baseWhere])
             : initial,
       ),
       knownForms = forms;

  static const title = 'Filters';
  static const searchInLabel = 'Search in';
  static const formLabel = 'Data';
  static const labels = {
    'createdBy': 'Created by',
    'sentBy': 'Sent by',
    'sentTo': 'Sent to',
    'taggedTo': 'Tagged to',
  };
  static const dateLabel = 'Date';
  static const sortLabel = 'Sort';
  static const advancedLabel = 'Advanced';
  static const approvalLabel = 'Approval';
  static const searchInHint = 'All records';
  static const anybody = 'Anybody';
  static const countingText = 'Counting the forms...';
  static const noFormText = 'No form has a record here.';
  static const noFormsYetText = 'No forms to choose from yet.';
  static const nobodyText = 'Nobody on these records.';
  static const conditionsUnavailableText =
      'Conditions are not available right now';
  static const conditionsLoadingText = 'Reading the fields...';
  static const conditionsNeedOneFormText =
      'Conditions work on one data form. Choose a single form to add them.';
  static const conditionsManyFormsText =
      'Conditions are for one data form only. With several forms they are not used.';
  static const applyLabel = 'Apply';
  static const clearLabel = 'Clear';

  final InboxRepository inbox;

  /// The entry the list shows anyway (the Me / My Team switch). A draft with
  /// no "Search in" starts on it.
  final String baseWhere;
  final bool isTeamShown;

  /// Form id -> caption of the forms the screen has read.
  final Map<String, String> knownForms;
  final void Function(InboxFilter) onApply;
  final void Function() onClear;
  final Duration wait;

  /// The panel of a first-run tour: it never reads anything.
  final bool isSample;

  /// The field kinds for conditions; null when there is no source for them.
  final InboxFieldKinds? fieldKinds;

  /// The shared approval list, for the Data counts of the approval entries
  /// and the Advanced ticks; null when the panel has none.
  final InboxApprovals? approvals;

  final Rx<InboxFilter> draft;
  final _answer = Rxn<_Answer>();

  /// The newest ask failed (every form is then offered).
  final hasFailed = false.obs;
  final isAdvanced = false.obs;

  /// Where the field kinds stand (failed when there is no source for them).
  late final Rx<InboxKindsState> kindsState =
      fieldKinds?.state ?? InboxKindsState.failed.obs;

  final _workers = <Worker>[];
  Timer? _timer;
  int _seq = 0;
  String _plannedKey = '';
  String _plannedGroup = '';

  @override
  void onInit() {
    super.onInit();
    _workers.addAll([
      ever(draft, (_) {
        _plan();
        _settle();
      }),
      // The reports are part of the Requests ask; a plan that reads the same
      // is left as it is.
      ever(inbox.people.last, (_) => _plan()),
    ]);
    isAdvanced.value =
        draft.value.blocks.any((b) => b.isActive) ||
        draft.value.approvalPick.isNotEmpty;
    final a = approvals;
    if (a != null) {
      _workers.addAll([
        ever(a.approvals.all, (_) => _onApprovals()),
        ever(a.approvals.hasRead, (_) => _onApprovals()),
      ]);
    }
    _ensureKinds();
    fireAndLog('inbox_filter_controller', _loadPeople);
    _plan();
    _settle();
  }

  // ---- the lists ----------------------------------------------------------------

  /// The reports' names (`records.people`), for Requests.
  List<String> get team => inbox.people.last.value?.team ?? const [];

  Future<void> _loadPeople() async {
    if (isSample) return;
    if (inbox.people.last.value != null) return;
    try {
      await inbox.loadPeople();
    } on SocketCallError catch (e) {
      AppLog.w('inbox_filter_controller', 'people not read: ${e.code}');
    }
  }

  /// Entries of "Search in" the panel offers: My Team only with reports.
  List<InboxChoice> get searchInChoices => [
    for (final w in InboxWhere.offered)
      if (w != InboxWhere.team || isTeamShown)
        InboxChoice(w, InboxWhere.labels[w] ?? w),
  ];

  _Answer? get _shown {
    final a = _answer.value;
    return a != null && a.group == draft.value.group ? a : null;
  }

  /// Is "Search in" read by the server (not only approvals and reminders)?
  bool get isOnServer => draft.value.serverViews(team).isNotEmpty;

  /// Is the answer shown the ask of the panel as it stands?
  bool get isFresh {
    final a = _shown;
    if (a == null) return false;
    return a.key == _keyOf(draft.value);
  }

  // ---- the approvals' part of the lists ---------------------------------------

  List<Approval> get _approvalList => approvals?.approvals.all ?? const [];

  bool get _hasApprovalEntry => InboxApprovalRows(draft.value).hasApprovalEntry;

  /// The approvals are needed for the counts and not read yet.
  bool get _isWaitingForApprovals =>
      _hasApprovalEntry && approvals != null && !approvals!.isRead;

  /// How many approvals each form has under the panel as it stands
  /// (`approvalFormCounts`); empty when no approval entry is chosen.
  Map<String, int> get ownCounts =>
      InboxApprovalRows(draft.value).formCounts(_approvalList);

  /// The forms with a record or an approval under the other lines, with how
  /// many (a record counts once; the approval entries add their own). While
  /// they are counted nothing is offered (the whole list would be wrong for
  /// a moment); when they cannot be counted every form is.
  Map<String, int>? get _counts {
    final own = ownCounts;
    if (!isOnServer) {
      if (!_hasApprovalEntry) return null;
      return _isWaitingForApprovals ? null : own;
    }
    final server = _shown?.facets.forms;
    if (server == null) return null;
    if (_isWaitingForApprovals) return null;
    return {
      for (final id in {...server.keys, ...own.keys})
        id: (server[id] ?? 0) + (own[id] ?? 0),
    };
  }

  bool get _hasCountFailed =>
      hasFailed.value ||
      (_isWaitingForApprovals && (approvals?.hasFailedRead ?? false));

  List<InboxChoice> get formChoices {
    final counts = _counts;
    final known = [for (final e in knownForms.entries) e]
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    if (counts != null) {
      final unknown =
          counts.keys.where((id) => !knownForms.containsKey(id)).toList()
            ..sort();
      return [
        for (final id in [for (final e in known) e.key, ...unknown])
          if ((counts[id] ?? 0) > 0)
            InboxChoice(id, '${knownForms[id] ?? id} (${counts[id]})'),
      ];
    }
    return _hasCountFailed
        ? [for (final e in known) InboxChoice(e.key, e.value)]
        : const [];
  }

  /// All forms of the screen, for the Advanced blocks (no counts).
  List<InboxChoice> get allFormChoices => [
    for (final e
        in knownForms.entries.toList()..sort(
          (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
        ))
      InboxChoice(e.key, e.value),
  ];

  String get formsEmptyText => _counts != null
      ? noFormText
      : _hasCountFailed
      ? noFormsYetText
      : countingText;

  /// How one person is shown: the name people.cards gave, else the user name.
  String nameOf(String user) {
    inbox.cardRevision.value;
    final n = inbox.cardOf(user)?.name ?? '';
    return n.isEmpty ? user : n;
  }

  /// The people one line offers: exactly who is on the records when the
  /// server answered; else the Inbox's own lists, "Me" first.
  List<InboxChoice> peopleChoices(String key) {
    final who = _shown?.facets;
    final base = who != null
        ? inboxPeopleChoices(who.peopleOf(key), nameOf, isListed: true)
        : inboxPeopleChoices(_fallbackUsers(key), nameOf);
    return [for (final c in base) InboxChoice(c.id, c.label)];
  }

  /// The people a block offers: the Inbox's own lists, "Me" first (a block
  /// has no counts of its own).
  List<InboxChoice> blockPeopleChoices(String key) => [
    for (final c in inboxPeopleChoices(_fallbackUsers(key), nameOf))
      InboxChoice(c.id, c.label),
  ];

  bool get hasPeopleAnswer => _shown != null;

  List<String> _fallbackUsers(String key) {
    final p = inbox.people.last.value;
    return switch (key) {
      'createdBy' => p?.team ?? const [],
      'sentBy' => p?.sentBy ?? const [],
      'sentTo' => p?.sentTo ?? const [],
      'taggedTo' => [...?p?.sentTo, ...?p?.team],
      _ => const [],
    };
  }

  /// A short line of what a list holds, for its row.
  String summaryOf(List<String> ids, List<InboxChoice> choices, String empty) {
    if (ids.isEmpty) return empty;
    final labels = [
      for (final id in ids)
        choices.where((c) => c.id == id).map(_plainLabel).firstOrNull ??
            (id == 'me' ? 'Me' : nameOf(id)),
    ];
    return labels.join(', ');
  }

  String _plainLabel(InboxChoice c) =>
      c.label.replaceFirst(RegExp(r' \(\d+\)$'), '');

  // ---- changes ------------------------------------------------------------------

  void setWheres(List<String> next) => draft.value = draft.value.copyWith(
    wheres: InboxWhere.choice(draft.value.wheres, next),
  );

  void setForms(List<String> next) =>
      draft.value = draft.value.copyWith(forms: next);

  void setPeople(String key, List<String> next) =>
      draft.value = draft.value.withPeople(key, next);

  void setFrom(String day) => draft.value = draft.value.copyWith(from: day);

  void setTo(String day) => draft.value = draft.value.copyWith(to: day);

  void setSortChoice(String choice) =>
      draft.value = draft.value.withSortChoice(choice);

  void toggleAdvanced() {
    isAdvanced.value = !isAdvanced.value;
    if (isAdvanced.value && draft.value.blocks.isEmpty) addBlock();
    _ensureKinds();
  }

  bool get canAddBlock =>
      draft.value.blocks.length < InboxFilterLimits.maxBlocks;

  void addBlock() {
    if (!canAddBlock) return;
    draft.value = draft.value.copyWith(
      blocks: [...draft.value.blocks, InboxBlock()],
    );
  }

  void removeBlock(String id) => draft.value = draft.value.copyWith(
    blocks: [
      for (final b in draft.value.blocks)
        if (b.id != id) b,
    ],
  );

  void changeBlock(String id, InboxBlock Function(InboxBlock) change) {
    draft.value = draft.value.copyWith(
      blocks: [for (final b in draft.value.blocks) b.id == id ? change(b) : b],
    );
  }

  /// A block's forms: another form, or a second one, drops its conditions (a
  /// field belongs to one form); the same single form keeps them
  /// (`FilterBlocks.jsx`).
  void setBlockForms(String id, List<String> forms) {
    changeBlock(id, (b) {
      final isSame =
          forms.length == 1 &&
          b.forms.length == 1 &&
          forms.first == b.forms.first;
      return b.copyWith(forms: forms, conditions: isSame ? b.conditions : []);
    });
    _ensureKinds();
  }

  // ---- conditions ---------------------------------------------------------------

  /// The kinds are read only while the Advanced fold is open and a block names
  /// exactly one form; a read held already is not read again.
  void _ensureKinds() {
    final k = fieldKinds;
    if (k == null || !isAdvanced.value) return;
    if (!draft.value.blocks.any((b) => b.forms.length == 1)) return;
    fireAndLog('inbox_filter_controller', () => k.load());
  }

  /// Does the block take conditions (exactly one form)?
  bool hasOneForm(InboxBlock b) => b.forms.length == 1;

  /// The fields of the block's one form (empty until they are known).
  List<InboxChoice> fieldChoices(InboxBlock b) => [
    for (final f in _fieldsOf(b)) InboxChoice(f.name, f.caption),
  ];

  List<InboxFieldInfo> _fieldsOf(InboxBlock b) => hasOneForm(b)
      ? fieldKinds?.fieldsOf(b.forms.single) ?? const []
      : const [];

  /// The kind of the condition's field (text when it is not known).
  String kindOfCondition(InboxBlock b, InboxCondition c) => hasOneForm(b)
      ? fieldKinds?.kindOf(b.forms.single, c.field) ?? 'text'
      : 'text';

  /// The operators of the condition's field kind, as choices.
  List<InboxChoice> operatorChoices(InboxBlock b, InboxCondition c) => [
    for (final (id, words) in InboxOps.of(kindOfCondition(b, c)))
      InboxChoice(id, words),
  ];

  bool canAddCondition(InboxBlock b) =>
      hasOneForm(b) &&
      b.conditions.length < InboxFilterLimits.maxConditions &&
      _fieldsOf(b).isNotEmpty;

  void addCondition(String blockId) {
    changeBlock(blockId, (b) {
      if (!canAddCondition(b)) return b;
      return b.copyWith(conditions: [...b.conditions, InboxCondition()]);
    });
  }

  void removeCondition(String blockId, String id) => changeBlock(
    blockId,
    (b) => b.copyWith(
      conditions: [
        for (final c in b.conditions)
          if (c.id != id) c,
      ],
    ),
  );

  void _changeCondition(
    String blockId,
    String id,
    InboxCondition Function(InboxBlock, InboxCondition) change,
  ) => changeBlock(
    blockId,
    (b) => b.copyWith(
      conditions: [for (final c in b.conditions) c.id == id ? change(b, c) : c],
    ),
  );

  /// Another field: its kind's first operator, and the values start again
  /// (a yes/no field starts on No).
  void setConditionField(String blockId, String id, String field) =>
      _changeCondition(blockId, id, (b, c) {
        final kind = hasOneForm(b)
            ? fieldKinds?.kindOf(b.forms.single, field) ?? 'text'
            : 'text';
        return c.copyWith(
          field: field,
          op: InboxOps.of(kind).first.$1,
          value: kind == 'bool' ? 'false' : '',
          value2: '',
        );
      });

  void setConditionOp(String blockId, String id, String op) => _changeCondition(
    blockId,
    id,
    (b, c) => c.copyWith(op: op, value2: op == 'between' ? c.value2 : ''),
  );

  void setConditionValue(
    String blockId,
    String id, {
    String? value,
    String? value2,
  }) => _changeCondition(
    blockId,
    id,
    (b, c) => c.copyWith(value: value, value2: value2),
  );

  void setConditionJoin(String blockId, String id, String join) =>
      _changeCondition(blockId, id, (b, c) => c.copyWith(join: join));

  /// How many lines say something (the header's "N set").
  int get count => draft.value.filterCount(baseWhere: baseWhere);

  /// How many Advanced blocks say something.
  int get advancedCount =>
      draft.value.blocks.where((b) => b.isActive).length +
      (draft.value.approvalPick.isNotEmpty ? 1 : 0);

  // ---- Advanced > Approval ------------------------------------------------------

  /// Is a form named that has an approval flow (its answers are offered, and
  /// not before)?
  bool get isApprovalOffered =>
      InboxApprovalRows(draft.value).hasApprovalForm(_approvalList);

  void toggleApprovalPick(String id) {
    final now = draft.value.approvalPick;
    draft.value = draft.value.copyWith(
      approvalPick: now.contains(id)
          ? [
              for (final a in now)
                if (a != id) a,
            ]
          : [...now, id],
    );
  }

  void _onApprovals() => _settle();

  /// What the web's effects do when the lists change: a form that has no
  /// record or approval here any more is let go, and the ticks go when no
  /// named form has an approval flow. Only once the approvals are read.
  void _settle() {
    final a = approvals;
    if (a == null || !a.isRead) return;
    var next = draft.value;
    if (next.approvalPick.isNotEmpty && !isApprovalOffered) {
      next = next.copyWith(approvalPick: const []);
    }
    final counts = _counts;
    if (counts != null && (!isOnServer || isFresh)) {
      final kept = [
        for (final id in next.forms)
          if ((counts[id] ?? 0) > 0) id,
      ];
      if (kept.length != next.forms.length) next = next.copyWith(forms: kept);
    }
    if (!identical(next, draft.value)) draft.value = next;
  }

  /// Nothing was applied before; the draft goes to the Inbox.
  void apply() {
    _stop();
    onApply(draft.value);
  }

  /// Everything back to nothing, and the Inbox with it.
  void clear() {
    _stop();
    onClear();
  }

  // ---- facets -------------------------------------------------------------------

  String _keyOf(InboxFilter f) {
    try {
      return jsonEncode(f.toFacetQuery(team: team).toArgs(limit: 1));
    } on InboxQueryError {
      return '';
    }
  }

  /// Asks again only when the ask or its group changed (the web's effect
  /// depends on both): a change of a line the facets do not read is no new
  /// ask.
  void _plan() {
    if (isSample) return;
    final f = draft.value;
    if (f.serverViews(team).isEmpty) return;
    final key = _keyOf(f);
    if (key.isEmpty || (key == _plannedKey && f.group == _plannedGroup)) return;
    _plannedKey = key;
    _plannedGroup = f.group;
    _timer?.cancel();
    final mine = ++_seq;
    _timer = Timer(wait, () => _ask(mine, f, key));
  }

  Future<void> _ask(int mine, InboxFilter f, String key) async {
    try {
      final read = await inbox.queryFacets(f.toFacetQuery(team: team));
      if (mine != _seq || read == null) return;
      _answer.value = _Answer(f.group, key, read);
      hasFailed.value = false;
      _learn(read);
      _dropGone(read);
    } on SocketCallError catch (e) {
      AppLog.w('inbox_filter_controller', 'facets not read: ${e.code}');
      if (mine == _seq) hasFailed.value = true;
    } on InboxQueryError catch (e) {
      AppLog.w('inbox_filter_controller', 'facets refused: ${e.message}');
      if (mine == _seq) hasFailed.value = true;
    }
  }

  void _learn(InboxFacets read) {
    final names = {
      for (final k in inboxPeopleKeys) ...read.peopleOf(k),
      ...team,
    }..remove('me');
    if (names.isEmpty) return;
    fireAndLog('inbox_filter_controller', () => inbox.loadCards(names));
  }

  /// A form or a person that has no record here any more is let go (the
  /// answer is for the panel as it stands).
  void _dropGone(InboxFacets read) {
    var next = draft.value;
    var isChanged = false;
    final own = ownCounts;
    final forms = _isWaitingForApprovals
        ? next.forms
        : [
            for (final id in next.forms)
              if ((read.forms[id] ?? 0) + (own[id] ?? 0) > 0) id,
          ];
    if (forms.length != next.forms.length) {
      next = next.copyWith(forms: forms);
      isChanged = true;
    }
    for (final k in inboxPeopleKeys) {
      final kept = [
        for (final u in next.peopleOf(k))
          if (read.peopleOf(k).contains(u)) u,
      ];
      if (kept.length != next.peopleOf(k).length) {
        next = next.withPeople(k, kept);
        isChanged = true;
      }
    }
    if (isChanged) draft.value = next;
  }

  /// Has the sheet closed this panel?
  bool isDisposed = false;

  /// A live event: ask for the lists again, whatever they were.
  void refreshFacets() {
    _plannedKey = '';
    _plan();
  }

  void _stop() {
    _timer?.cancel();
    _seq++;
  }

  @override
  void onClose() {
    isDisposed = true;
    _stop();
    for (final w in _workers) {
      w.dispose();
    }
    super.onClose();
  }
}
