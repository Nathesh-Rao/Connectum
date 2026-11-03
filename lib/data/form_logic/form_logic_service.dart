import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:get/get.dart';
import 'package:quickjs_engine/quickjs_engine.dart';

import 'form_logic_assets.dart';

/// What a call to the logic gives back: a value, or the reason there is none.
/// Calls never throw.
class FormLogicResult<T> {
  const FormLogicResult.ok(T this.value) : error = null;
  const FormLogicResult.failed(String this.error) : value = null;

  final T? value;
  final String? error;

  bool get isOk => error == null;
}

/// The form logic (`ConnectumFormLogic`, JavaScript) in one QuickJS engine that
/// lives in a background isolate for as long as the app does. Plain JSON goes
/// in and out; the UI thread only waits on a port. A call that takes longer
/// than [timeout] ends with an error and the engine is started again.
class FormLogicService extends GetxService {
  static const timeout = Duration(seconds: 4);

  Future<void>? _starting;
  Isolate? _isolate;
  SendPort? _port;
  ReceivePort? _replies;
  final _waiting = <int, Completer<String>>{};
  int _seq = 0;
  String _dateFormat = 'dd/mm/yyyy';
  FormLogicAssets? _assets;

  Future<FormLogicResult<Map<String, dynamic>>> applyFormCalcs(
    List<Map<String, dynamic>> fields,
    List<Map<String, dynamic>> grids,
    Map<String, dynamic> values,
  ) => _map('applyFormCalcs', [fields, grids, values]);

  Future<FormLogicResult<String?>> fieldRuleError(
    Map<String, dynamic> field,
    Object? value,
    Map<String, dynamic> valuesWithBlanks,
  ) async {
    final r = await _call('fieldRuleError', [field, value, valuesWithBlanks]);
    if (!r.isOk) return FormLogicResult.failed(r.error!);
    final v = r.value;
    return FormLogicResult.ok(v?.toString());
  }

  Future<FormLogicResult<Object?>> evaluateExpression(
    String expr,
    Map<String, dynamic> values,
  ) => _call('evaluateExpression', [expr, values]);

  Future<FormLogicResult<Map<String, dynamic>>> withBlanks(
    List<String> ids,
    Map<String, dynamic> values,
  ) => _map('withBlanks', [ids, values]);

  Future<FormLogicResult<List<String>>> usedFields(
    String expr,
    List<String> ids,
  ) async {
    final r = await _call('usedFields', [expr, ids]);
    if (!r.isOk) return FormLogicResult.failed(r.error!);
    final v = r.value;
    return FormLogicResult.ok(v is List ? v.map((e) => '$e').toList() : []);
  }

  Future<FormLogicResult<bool>> hasCalc(Map<String, dynamic> field) =>
      _bool('hasCalc', field);

  Future<FormLogicResult<bool>> canCalc(Map<String, dynamic> field) =>
      _bool('canCalc', field);

  /// `dd/mm/yyyy` (the default) or `mm/dd/yyyy`. Kept and applied again if the
  /// engine has to be restarted.
  Future<FormLogicResult<void>> setDateFormat(String format) async {
    _dateFormat = format;
    final r = await _call('setDateFormat', [format]);
    return r.isOk
        ? const FormLogicResult.ok(null)
        : FormLogicResult.failed(r.error!);
  }

  Future<FormLogicResult<Map<String, dynamic>>> _map(
    String op,
    List<Object?> args,
  ) async {
    final r = await _call(op, args);
    if (!r.isOk) return FormLogicResult.failed(r.error!);
    final v = r.value;
    return v is Map
        ? FormLogicResult.ok(v.cast<String, dynamic>())
        : const FormLogicResult.failed('unexpected answer');
  }

  Future<FormLogicResult<bool>> _bool(String op, Object? arg) async {
    final r = await _call(op, [arg]);
    return r.isOk
        ? FormLogicResult.ok(r.value == true)
        : FormLogicResult.failed(r.error!);
  }

  Future<FormLogicResult<Object?>> _call(String op, List<Object?> args) async {
    try {
      final String payload;
      try {
        payload = jsonEncode(args);
      } on Object {
        return const FormLogicResult.failed('values are not plain JSON');
      }
      await _start();
      final port = _port;
      if (port == null) {
        return const FormLogicResult.failed('engine not running');
      }
      final id = ++_seq;
      final done = Completer<String>();
      _waiting[id] = done;
      port.send([id, op, payload]);
      final String raw;
      try {
        raw = await done.future.timeout(timeout);
      } on TimeoutException {
        _waiting.remove(id);
        _stop('timed out');
        return FormLogicResult.failed(
          '$op timed out after ${timeout.inSeconds} s',
        );
      }
      final reply = jsonDecode(raw) as Map<String, dynamic>;
      if (reply['e'] != null) return FormLogicResult.failed('${reply['e']}');
      return FormLogicResult.ok(reply['v']);
    } on Object catch (e) {
      return FormLogicResult.failed(e.toString());
    }
  }

  Future<void> _start() => _starting ??= _spawn().whenComplete(() {
    if (_port == null) _starting = null;
  });

  Future<void> _spawn() async {
    final assets = _assets ??= await FormLogicAssets.loadVerified();
    final replies = ReceivePort();
    final ready = Completer<SendPort>();
    replies.listen((m) {
      if (m is SendPort) {
        ready.complete(m);
      } else if (m is String && !ready.isCompleted) {
        ready.completeError(m);
      } else if (m is List && m.length == 2) {
        _waiting.remove(m[0] as int)?.complete(m[1] as String);
      }
    });
    final isolate = await Isolate.spawn(_entry, [
      replies.sendPort,
      assets.shim,
      assets.bundle,
    ], onExit: replies.sendPort);
    try {
      _port = await ready.future.timeout(const Duration(seconds: 15));
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      replies.close();
      rethrow;
    }
    _isolate = isolate;
    _replies = replies;
    if (_dateFormat != 'dd/mm/yyyy') {
      _port!.send([
        0,
        'setDateFormat',
        jsonEncode([_dateFormat]),
      ]);
    }
  }

  void _stop(String why) {
    _isolate?.kill(priority: Isolate.immediate);
    _replies?.close();
    _isolate = null;
    _replies = null;
    _port = null;
    _starting = null;
    final pending = _waiting.values.toList();
    _waiting.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.complete(jsonEncode({'e': 'engine stopped: $why'}));
    }
  }

  @override
  void onClose() {
    _stop('closed');
    super.onClose();
  }

  static const _dispatch = r'''
var __call = function (op, argsJson) {
  var L = ConnectumFormLogic, a = JSON.parse(argsJson), r;
  var idOf = function (f) { return f.name; };
  switch (op) {
    case 'applyFormCalcs': r = L.applyFormCalcs(a[0], a[1], a[2], idOf); break;
    case 'fieldRuleError': r = L.fieldRuleError(a[0], a[1], a[2]); break;
    case 'evaluateExpression': r = L.evaluateExpression(a[0], a[1]); break;
    case 'withBlanks': r = L.withBlanks(a[0], a[1]); break;
    case 'usedFields': r = L.usedFields(a[0], a[1]); break;
    case 'hasCalc': r = L.hasCalc(a[0]); break;
    case 'canCalc': r = L.canCalc(a[0]); break;
    case 'setDateFormat': L.SetDateFormat(a[0]); r = null; break;
    default: throw new Error('unknown op ' + op);
  }
  return JSON.stringify({ v: r === undefined ? null : r });
};
''';

  static void _entry(List<Object?> boot) {
    final out = boot[0] as SendPort;
    final inbox = ReceivePort();
    QuickJsRuntime2? rt;
    String run(String code) {
      final r = rt!.evaluate(code);
      if (r.isError) throw StateError(r.stringResult);
      return r.stringResult;
    }

    try {
      rt = QuickJsRuntime2();
      run(boot[1] as String);
      run(boot[2] as String);
      run(_dispatch);
    } on Object catch (e) {
      out.send('engine failed to load: $e');
      return;
    }
    out.send(inbox.sendPort);
    inbox.listen((m) {
      final msg = m as List;
      String reply;
      try {
        final code = '__call(${jsonEncode(msg[1])}, ${jsonEncode(msg[2])})';
        reply = run(code);
      } on Object catch (e) {
        reply = jsonEncode({'e': e.toString()});
      }
      if (msg[0] != 0) out.send([msg[0], reply]);
    });
  }
}
