import 'dart:convert';
import 'dart:isolate';

import 'package:quickjs_engine/quickjs_engine.dart';

import 'form_logic_assets.dart';

class FormLogicReport {
  const FormLogicReport(this.raw);

  final Map<String, dynamic> raw;

  String? get error => raw['error'] as String?;
  int get loadMicros => raw['loadMicros'] as int;
  int get evalMedianMicros => raw['evalMedianMicros'] as int;
  Map<String, dynamic> get conformance =>
      raw['conformance'] as Map<String, dynamic>;
  Map<String, dynamic> get probe => raw['probe'] as Map<String, dynamic>;
  List<Map<String, dynamic>> get parity =>
      (raw['parity'] as List).cast<Map<String, dynamic>>();
  String get dartNow => raw['dartNow'] as String;
  int get dartOffsetMinutes => raw['dartOffsetMinutes'] as int;
}

class FormLogicRunner {
  const FormLogicRunner._();

  static Future<FormLogicReport> run(FormLogicAssets assets) async {
    final job = (
      shim: assets.shim,
      bundle: assets.bundle,
      conformance: assets.conformance,
      parity: assets.parity,
    );
    final json = await Isolate.run(() => _work(job));
    return FormLogicReport(jsonDecode(json) as Map<String, dynamic>);
  }

  static String _literal(String json) => 'JSON.parse(${jsonEncode(json)})';

  static const _probe = r'''
(function () {
  var L = ConnectumFormLogic, r = {};
  var ev = function (e) { return String(L.evaluateExpression(e, {})); };
  r.jsOffsetMinutes = -new Date().getTimezoneOffset();
  r.jsDate = ev('Date()');
  r.jsTime = ev('Time()');
  L.SetDateFormat('dd/mm/yyyy');
  r.dmyDate = ev('Date()');
  r.dmyLast = ev('LastDayOfMonth("03/04/2026")');
  L.SetDateFormat('mm/dd/yyyy');
  r.mdyDate = ev('Date()');
  r.mdyLast = ev('LastDayOfMonth("03/04/2026")');
  L.SetDateFormat('dd/mm/yyyy');
  return JSON.stringify(r);
})()
''';

  static const _parity = r'''
(function (input) {
  var L = ConnectumFormLogic, idOf = function (f) { return f.name; };
  var same = function (a, b) { return String(a) === String(b); };
  var out = [];
  input.cases.forEach(function (c) {
    var form = input.forms[c.form], diffs = [];
    try {
      if (c.kind === 'calc') {
        var res = L.applyFormCalcs(form.fields, form.grids, c.values, idOf);
        Object.keys(c.expect || {}).forEach(function (k) {
          if (!same(res[k], c.expect[k])) diffs.push(k + ': expected ' + c.expect[k] + ', got ' + res[k]);
        });
        (c.absent || []).forEach(function (k) {
          if (res[k] !== undefined && res[k] !== null && res[k] !== '') diffs.push(k + ': expected empty, got ' + res[k]);
        });
        (c.rows || []).forEach(function (row, i) {
          var got = ((res[form.grids[0].id] || [])[i]) || {};
          Object.keys(row).forEach(function (k) {
            if (!same(got[k], row[k])) diffs.push('row ' + (i + 1) + ' ' + k + ': expected ' + row[k] + ', got ' + got[k]);
          });
        });
      } else {
        var ids = form.fields.map(idOf);
        var field = form.fields.filter(function (f) { return f.name === c.field; })[0];
        var got2 = L.fieldRuleError(field, c.values[c.field], L.withBlanks(ids, c.values));
        if (got2 !== c.error) diffs.push('expected ' + JSON.stringify(c.error) + ', got ' + JSON.stringify(got2));
      }
    } catch (e) {
      diffs.push('ERROR: ' + (e && e.message));
    }
    out.push({ label: c.label, note: c.note || '', diffs: diffs });
  });
  return JSON.stringify(out);
})
''';

  static String _work(
    ({String shim, String bundle, String conformance, String parity}) job,
  ) {
    String run(QuickJsRuntime2 rt, String code) {
      final r = rt.evaluate(code);
      if (r.isError) throw StateError(r.stringResult);
      return r.stringResult;
    }

    final rt = QuickJsRuntime2();
    try {
      final load = Stopwatch()..start();
      run(rt, job.shim);
      run(rt, job.bundle);
      load.stop();

      final conformance = run(
        rt,
        'JSON.stringify(ConnectumFormLogic.runConformance('
        '${_literal(job.conformance)}))',
      );

      final dartNow = DateTime.now();
      final probe = run(rt, _probe);

      final parityInput = _literal(job.parity);
      final parity = run(rt, '($_parity)($parityInput)');

      const expr =
          "ConnectumFormLogic.evaluateExpression('qty*price+Length(name)', "
          "{qty: 3, price: 2.5, name: 'Asha'})";
      run(rt, expr);
      final times = <int>[];
      final sw = Stopwatch();
      for (var i = 0; i < 200; i++) {
        sw
          ..reset()
          ..start();
        rt.evaluate(expr);
        sw.stop();
        times.add(sw.elapsedMicroseconds);
      }
      times.sort();

      return jsonEncode({
        'loadMicros': load.elapsedMicroseconds,
        'evalMedianMicros': (times[99] + times[100]) ~/ 2,
        'conformance': jsonDecode(conformance),
        'probe': jsonDecode(probe),
        'parity': jsonDecode(parity),
        'dartNow': dartNow.toIso8601String(),
        'dartOffsetMinutes': dartNow.timeZoneOffset.inMinutes,
      });
    } on Object catch (e) {
      return jsonEncode({'error': e.toString()});
    } finally {
      rt.close();
    }
  }
}
