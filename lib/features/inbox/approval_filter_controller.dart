import 'package:get/get.dart';

import 'package:connectum/data/models/models.dart';
import 'inbox_approvals_controller.dart';
import 'inbox_filter_controller.dart';
import 'models/approval_entries.dart';
import 'models/approval_pane.dart';
import 'models/approval_panel.dart';
import 'models/inbox_filter.dart';

/// The Approvals filter panel (`ApprovalsFilterFab.jsx`): the draft, and what
/// its lines offer, read on the requests already loaded (`req.list`,
/// `req.team`). Nothing applies until [apply]; a draft left without it is
/// dropped. Memory only.
class ApprovalFilterController extends GetxController {
  ApprovalFilterController({
    required this.approvals,
    required ApprovalPanel initial,
  }) : draft = Rx<ApprovalPanel>(initial);

  static const title = 'Filters';
  static const searchInLabel = 'Search in';
  static const dataLabel = 'Data';
  static const raisedByLabel = 'Raised by';
  static const approverLabel = 'Approver';
  static const dateLabel = 'Date';
  static const sortLabel = 'Sort';
  static const advancedLabel = 'Advanced filter';
  static const noFormText = 'No form has a request here.';
  static const nobodyText = 'Nobody on these requests.';
  static const anybody = 'Anybody';
  static const noFieldsText =
      'The requests of this data carry no fields to filter by yet.';
  static const needOneFormText =
      'Conditions work on one data form. Choose a single form to add them.';
  static const manyFormsText =
      'Conditions are for one data form only. With several forms they are not used.';
  static const applyLabel = 'Apply';
  static const clearLabel = 'Clear';

  final InboxApprovals approvals;
  final Rx<ApprovalPanel> draft;
  final isAdvanced = false.obs;

  @override
  void onInit() {
    super.onInit();
    isAdvanced.value = draft.value.activeBlocks.isNotEmpty;
  }

  bool get hasTeam => approvals.hasTeam;

  /// The label of the chip the panel is for, shown beside the title.
  String get chipLabel => approvals.primary.value.label;

  /// How many lines say something (the header's "N set").
  int get count => draft.value.count;

  int get advancedCount => draft.value.activeBlocks.length;

  // ---- Search in ----------------------------------------------------------------

  /// The entries of the chip that is on, the person's own then the team's.
  List<ApprovalEntry> get entries =>
      ApprovalPanelRules.offered(approvals.primary.value, hasTeam);

  /// Grey text while nothing is ticked: what the toggle is showing.
  String get usualText => ApprovalPanelRules.usualText(
    approvals.primary.value,
    approvals.side.value,
    hasTeam: hasTeam,
  );

  void toggleEntry(ApprovalEntry e) {
    final now = draft.value.entries;
    draft.value = draft.value.copyWith(
      entries: now.contains(e)
          ? [
              for (final x in now)
                if (x != e) x,
            ]
          : [...now, e],
    );
  }

  // ---- the requests the lines are read on ---------------------------------------

  List<Approval> get _listed => [
    for (final a in approvals.pool)
      if (ApprovalPane.isListed(a)) a,
  ];

  // ---- Data ---------------------------------------------------------------------

  Map<String, String> get _forms => ApprovalPanelRules.formsOf(_listed);

  /// The forms that have requests under the other lines, with how many; a
  /// form that is ticked stays so it can be unticked.
  List<InboxChoice> get formChoices {
    final d = draft.value;
    final counts = ApprovalPanelRules.formCounts(
      approvals.pool,
      d,
      ApprovalPanelRules.effective(
        approvals.primary.value,
        approvals.side.value,
        d.entries,
        hasTeam: hasTeam,
      ),
      approvals.whoOf,
    );
    final forms = _forms;
    final ids = {
      ...counts.keys,
      for (final f in d.forms)
        if (forms.containsKey(f)) f,
    }.toList()..sort((a, b) => _label(forms, a).compareTo(_label(forms, b)));
    return [
      for (final id in ids)
        InboxChoice(id, '${forms[id] ?? id} (${counts[id] ?? 0})'),
    ];
  }

  String _label(Map<String, String> forms, String id) =>
      (forms[id] ?? id).toLowerCase();

  /// Every form that has a request, for the Advanced blocks (no counts).
  List<InboxChoice> get allFormChoices {
    final forms = _forms;
    final ids = forms.keys.toList()
      ..sort((a, b) => _label(forms, a).compareTo(_label(forms, b)));
    return [for (final id in ids) InboxChoice(id, forms[id] ?? id)];
  }

  String formName(String id) => _forms[id] ?? id;

  void setForms(List<String> next) =>
      draft.value = draft.value.copyWith(forms: next);

  // ---- People -------------------------------------------------------------------

  /// The people a line offers: only those on the loaded requests, by name.
  List<String> peopleOf(bool isApprover) {
    final users = isApprover
        ? ApprovalPanelRules.approversOf(_listed)
        : ApprovalPanelRules.askers(_listed);
    return users..sort(
      (a, b) => nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase()),
    );
  }

  String nameOf(String user) => approvals.nameOfUser(user);

  String? pictureOf(String user) => approvals.pictureOfUser(user);

  void setRaisedBy(List<String> next) =>
      draft.value = draft.value.copyWith(raisedBy: next);

  void setApprovers(List<String> next) =>
      draft.value = draft.value.copyWith(approvers: next);

  // ---- Date and order -----------------------------------------------------------

  void setFrom(String day) => draft.value = draft.value.copyWith(from: day);

  void setTo(String day) => draft.value = draft.value.copyWith(to: day);

  void setSort(String sort) => draft.value = draft.value.copyWith(sort: sort);

  // ---- Advanced -----------------------------------------------------------------

  void toggleAdvanced() {
    isAdvanced.value = !isAdvanced.value;
    if (isAdvanced.value && draft.value.blocks.isEmpty) addBlock();
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

  /// Another form, or a second one, drops the conditions (a field belongs to
  /// one form); the same single form keeps them.
  void setBlockForms(String id, List<String> forms) => changeBlock(id, (b) {
    final isSame =
        forms.length == 1 &&
        b.forms.length == 1 &&
        forms.first == b.forms.first;
    return b.copyWith(forms: forms, conditions: isSame ? b.conditions : []);
  });

  bool hasOneForm(InboxBlock b) => b.forms.length == 1;

  /// The fields a block of one form offers: the captions its requests carry.
  List<ApprovalField> fieldsOf(InboxBlock b) => hasOneForm(b)
      ? ApprovalPanelRules.fieldsOf(_listed, b.forms.single)
      : const [];

  List<InboxChoice> fieldChoices(InboxBlock b) => [
    for (final f in fieldsOf(b)) InboxChoice(f.caption, f.caption),
  ];

  /// The kind of the condition's field, read from the values the requests
  /// carry (text when unknown).
  String kindOfCondition(InboxBlock b, InboxCondition c) =>
      fieldsOf(
        b,
      ).where((f) => f.caption == c.field).map((f) => f.kind).firstOrNull ??
      'text';

  List<InboxChoice> operatorChoices(InboxBlock b, InboxCondition c) => [
    for (final (id, words) in InboxOps.of(kindOfCondition(b, c)))
      InboxChoice(id, words),
  ];

  bool canAddCondition(InboxBlock b) =>
      hasOneForm(b) &&
      b.conditions.length < InboxFilterLimits.maxConditions &&
      fieldsOf(b).isNotEmpty;

  void addCondition(String blockId) => changeBlock(blockId, (b) {
    if (!canAddCondition(b)) return b;
    return b.copyWith(conditions: [...b.conditions, InboxCondition()]);
  });

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

  /// Another field: its kind's first operator, and the values start again.
  void setConditionField(String blockId, String id, String caption) =>
      _changeCondition(blockId, id, (b, c) {
        final kind =
            fieldsOf(b)
                .where((f) => f.caption == caption)
                .map((f) => f.kind)
                .firstOrNull ??
            'text';
        return c.copyWith(
          field: caption,
          op: InboxOps.of(kind).first.$1,
          value: '',
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

  // ---- Apply and Clear ------------------------------------------------------------

  void apply() => approvals.applyPanel(draft.value);

  void clear() => approvals.clearPanel();
}
