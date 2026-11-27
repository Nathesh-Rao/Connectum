import 'package:get/get.dart';

import '../../../data/smart_view/engine/sv_engine.dart';
import '../../../data/smart_view/engine/sv_values.dart';
import '../../../data/smart_view/sv_columns.dart';
import '../../../data/smart_view/sv_query.dart';
import '../../../data/smart_view/sv_team.dart';

/// One line of the filter sheet while it is being edited.
class SvDraftRow {
  const SvDraftRow({
    required this.id,
    required this.col,
    required this.op,
    this.value,
  });

  final int id;
  final String col;
  final String op;
  final Object? value;

  SvCondition get condition => SvCondition(col, op, value);
}

/// How a draft row's value is edited.
enum SvValueKind {
  none,
  text,
  number,
  numberRange,
  date,
  dateRange,
  choice,
  tristate,
}

/// The sheet's edits, kept apart from the view's query until Apply: closing
/// the sheet drops them. The live count runs the engine on the loaded rows.
class SvFilterDraft {
  SvFilterDraft(this.input, SmartViewQuery start)
    : search = start.search,
      scope = start.scope {
    members.assignAll(SvTeam.membersOf(start.conditions));
    linked.assignAll(SvTeam.waysOf(start.conditions));
    for (final c in start.conditions) {
      if (SvTeam.isTeamLine(c)) continue;
      rows.add(SvDraftRow(id: _seq++, col: c.col, op: c.op, value: c.value));
    }
  }

  static const maxChoices = 60;

  final SvEngineInput input;
  final String search;
  final String? scope;
  final rows = <SvDraftRow>[].obs;

  /// The "My team" and "Linked as" lines: not columns, so not in [rows].
  final members = <String>[].obs;
  final linked = <String>[].obs;
  int _seq = 0;

  bool get hasAny => rows.isNotEmpty || members.isNotEmpty || linked.isNotEmpty;

  void toggleMember(String user) => _toggle(members, user);

  void toggleWay(String id) => _toggle(linked, id);

  static void _toggle(RxList<String> list, String v) {
    if (!list.remove(v)) list.add(v);
  }

  /// Every column a filter can be put on (files have no useful value).
  List<SvColumn> get fields => [
    for (final c in input.columns.columns)
      if (c.type != SvColType.file) c,
  ];

  SvColumn? colOf(String key) {
    for (final c in input.columns.columns) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// A status or select column offers its distinct values as chips, unless
  /// there are too many of them.
  bool isChoice(SvColumn c) =>
      (c.type == SvColType.status || c.type == SvColType.select) &&
      input.distinct(c.key, limit: maxChoices).length <= maxChoices;

  List<String> opsOf(SvColumn c) {
    if (c.type == SvColType.checkbox) return const ['', 'true', 'false'];
    if (isChoice(c)) return const ['in', 'empty', 'filled'];
    return SvEngine.opsFor(SvEngineInput.typeOf(c.type));
  }

  SvValueKind kindOf(SvColumn c, String op) {
    if (c.type == SvColType.checkbox) return SvValueKind.tristate;
    switch (op) {
      case 'empty' || 'filled' || 'true' || 'false':
        return SvValueKind.none;
      case 'in':
        return SvValueKind.choice;
      case 'between':
        return SvEngineInput.typeOf(c.type) == EngineType.number
            ? SvValueKind.numberRange
            : SvValueKind.dateRange;
    }
    return switch (SvEngineInput.typeOf(c.type)) {
      EngineType.number => SvValueKind.number,
      EngineType.date => SvValueKind.date,
      _ => SvValueKind.text,
    };
  }

  /// A new line on the first field.
  void add() {
    final first = fields.first;
    rows.add(SvDraftRow(id: _seq++, col: first.key, op: opsOf(first).first));
  }

  void remove(int id) => rows.removeWhere((r) => r.id == id);

  void clear() {
    rows.clear();
    members.clear();
    linked.clear();
  }

  void _replace(int id, SvDraftRow Function(SvDraftRow) f) {
    final i = rows.indexWhere((r) => r.id == id);
    if (i >= 0) rows[i] = f(rows[i]);
  }

  void setCol(int id, SvColumn c) => _replace(
    id,
    (r) =>
        r.col == c.key ? r : SvDraftRow(id: id, col: c.key, op: opsOf(c).first),
  );

  /// A new operator keeps the value only when it is edited the same way.
  void setOp(int id, String op) => _replace(id, (r) {
    final c = colOf(r.col);
    final same = c != null && kindOf(c, r.op) == kindOf(c, op);
    return SvDraftRow(id: id, col: r.col, op: op, value: same ? r.value : null);
  });

  void setValue(int id, Object? value) => _replace(
    id,
    (r) => SvDraftRow(id: id, col: r.col, op: r.op, value: value),
  );

  /// The column conditions the engine applies.
  List<SvCondition> get columnConditions => [for (final r in rows) r.condition];

  /// Everything the sheet applies: the columns' conditions and the two team
  /// lines (a line with no choice is left out).
  List<SvCondition> get conditions =>
      SvTeam.withLines(columnConditions, members.toList(), linked.toList());

  int get total => input.rows.length;

  int get count =>
      input.count(search: search, scope: scope, conditions: columnConditions);
}
