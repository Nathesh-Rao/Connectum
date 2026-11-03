import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/form_option.dart';
import '../models/ids.dart';
import '../repositories/form_options_repository.dart';
import '../socket/socket_service.dart';
import 'form_logic_service.dart';
import 'form_logic_values.dart';

/// A form definition split the way the logic wants it: the ordinary fields,
/// and each grid section with the fields of its rows.
class FormShape {
  FormShape(this.tstruct)
    : gridNames = {
        for (final s in tstruct['sections'] as List? ?? const [])
          if (s is Map && s['grid'] == true) idText(s['name']),
      } {
    for (final f in tstruct['fields'] as List? ?? const []) {
      if (f is! Map) continue;
      final field = f.cast<String, dynamic>();
      all.add(field);
      if (gridNames.contains(idText(field['section']))) {
        grids.putIfAbsent(idText(field['section']), () => []).add(field);
      } else {
        fields.add(field);
      }
    }
  }

  final Map<String, dynamic> tstruct;
  final Set<String> gridNames;
  final all = <Map<String, dynamic>>[];
  final fields = <Map<String, dynamic>>[];
  final grids = <String, List<Map<String, dynamic>>>{};

  /// The `grids` argument of `applyFormCalcs`.
  List<Map<String, dynamic>> get gridList => [
    for (final g in gridNames)
      {'id': g, 'fields': grids[g] ?? const <Map<String, dynamic>>[]},
  ];

  List<String> get fieldIds => [for (final f in fields) idText(f['name'])];

  Map<String, dynamic> toLogic(Map<String, dynamic> values) =>
      FormLogicValues.toLogic(all, gridNames, values);
}

/// How one sample form did against `cases.json`.
class SampleFormResult {
  SampleFormResult(this.name, this.caption);

  final String name;
  final String caption;
  int calcTotal = 0;
  int calcPassed = 0;
  int rulesTotal = 0;
  int rulesPassed = 0;
  String? error;
  final failures = <String>[];

  int get total => calcTotal + rulesTotal;
  int get passed => calcPassed + rulesPassed;
  bool get isOk => error == null && passed == total;

  String get line {
    if (error != null) return '$name: ERROR $error';
    final parts = [
      if (calcTotal > 0) 'calc $calcPassed/$calcTotal',
      if (rulesTotal > 0) 'rules $rulesPassed/$rulesTotal',
    ];
    return '$name: ${parts.isEmpty ? 'no calc or rule cases' : parts.join(', ')}';
  }
}

/// Read-only access to the `sample_*` forms and the check of the form logic
/// against their cases. Only `options.list` (already cached) and
/// `tstruct.get` / `tstruct.user.get` are sent; nothing is saved or submitted.
class SampleForms {
  SampleForms(this._socket, this._options, this._logic);

  final SocketService _socket;
  final FormOptionsRepository _options;
  final FormLogicService _logic;

  Map<String, dynamic>? _cases;

  /// The sample forms this person can open.
  Future<List<FormOption>> list() async {
    if (_socket.isOnline) await _options.refresh();
    final seen = <String>{};
    return [
      for (final o in _options.options)
        if (o.isForm && o.target.startsWith('sample_') && seen.add(o.target)) o,
    ]..sort((a, b) => a.target.compareTo(b.target));
  }

  /// The definition as the server returned it (`tstruct`).
  Future<Map<String, dynamic>> definition(FormOption o) async {
    final data = await _socket.sdCall(
      o.targetScope == 'user' ? 'tstruct.user.get' : 'tstruct.get',
      {'name': o.target},
    );
    return (data['tstruct'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _casesOf(String name) async {
    _cases ??=
        jsonDecode(
              await rootBundle.loadString(
                'assets/form_logic/sample_cases.json',
              ),
            )
            as Map<String, dynamic>;
    final c = _cases![name];
    return c is Map ? c.cast<String, dynamic>() : const {};
  }

  Future<SampleFormResult> check(FormOption o) async {
    final result = SampleFormResult(o.target, o.caption);
    try {
      final shape = FormShape(await definition(o));
      final cases = await _casesOf(o.target);
      for (final c in (cases['calc'] as List? ?? const [])) {
        result.calcTotal++;
        final diffs = await _calcCase(
          shape,
          (c as Map).cast<String, dynamic>(),
        );
        if (diffs.isEmpty) {
          result.calcPassed++;
        } else {
          result.failures.add(
            'calc ${jsonEncode(c['values'])}\n  ${diffs.join('\n  ')}',
          );
        }
      }
      for (final c in (cases['rules'] as List? ?? const [])) {
        result.rulesTotal++;
        final diff = await _ruleCase(shape, (c as Map).cast<String, dynamic>());
        if (diff == null) {
          result.rulesPassed++;
        } else {
          result.failures.add(
            'rule ${c['field']} ${jsonEncode(c['values'])}\n  $diff',
          );
        }
      }
    } on SocketCallError catch (e) {
      result.error = '${e.code} ${e.message}'.trim();
    } on Object catch (e) {
      result.error = e.toString();
    }
    return result;
  }

  static bool _same(Object? a, Object? b) => idText(a) == idText(b);

  Future<List<String>> _calcCase(
    FormShape shape,
    Map<String, dynamic> c,
  ) async {
    final values = shape.toLogic((c['values'] as Map).cast<String, dynamic>());
    final r = await _logic.applyFormCalcs(shape.fields, shape.gridList, values);
    if (!r.isOk) return [r.error!];
    final res = r.value!;
    final diffs = <String>[];
    ((c['expect'] as Map?) ?? const {}).forEach((k, want) {
      if (!_same(res[k], want)) diffs.add('$k: expected $want, got ${res[k]}');
    });
    for (final k in (c['absent'] as List? ?? const [])) {
      if (idText(res[k]).isNotEmpty) {
        diffs.add('$k: expected empty, got ${res[k]}');
      }
    }
    final rows = c['rows'] as List? ?? const [];
    if (rows.isNotEmpty && shape.gridNames.isNotEmpty) {
      final got = res[shape.gridNames.first] as List? ?? const [];
      for (var i = 0; i < rows.length; i++) {
        final cells = i < got.length && got[i] is Map
            ? got[i] as Map
            : const {};
        (rows[i] as Map).forEach((k, want) {
          if (!_same(cells[k], want)) {
            diffs.add('row ${i + 1} $k: expected $want, got ${cells[k]}');
          }
        });
      }
    }
    return diffs;
  }

  Future<String?> _ruleCase(FormShape shape, Map<String, dynamic> c) async {
    final name = idText(c['field']);
    final field = shape.fields.where((f) => f['name'] == name).firstOrNull;
    if (field == null) return 'field $name is not in the form';
    final values = shape.toLogic((c['values'] as Map).cast<String, dynamic>());
    final blanks = await _logic.withBlanks(shape.fieldIds, values);
    if (!blanks.isOk) return blanks.error;
    final r = await _logic.fieldRuleError(field, values[name], blanks.value!);
    if (!r.isOk) return r.error;
    final want = c['error'];
    return _same(r.value, want) && (r.value == null) == (want == null)
        ? null
        : 'expected ${jsonEncode(want)}, got ${jsonEncode(r.value)}';
  }
}
